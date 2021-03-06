#import "UINibDecoderForNibArchiveV1.h"
#import "UIProxyObject.h"
#import "UIImageNibPlaceholder.h"
#import "UIGeometry.h"


typedef struct {
    NSUInteger indexOfClass;
    NSUInteger indexOfFirstValue;
    NSUInteger numberOfValues;
} UINibDecoderObjectEntry;

typedef struct {
    NSUInteger indexOfKey;
    NSUInteger type;
    void const* data;
} UINibDecoderValueEntry;

enum {
    kValueTypeByte                  = 0x00,
    kValueTypeShort                 = 0x01,
    kValueTypeConstantEqualsZero    = 0x04,
    kValueTypeConstantEqualsOne     = 0x05,
    kValueTypeFloat32               = 0x06,
    kValueTypeFloat64               = 0x07,
    kValueTypeData                  = 0x08,
    kValueTypeNull                  = 0x09,
    kValueTypeObject                = 0x0A,
};

enum {
    kInlinedValueTypeArray          = 0x05,
};


static NSString* const kIBFilesOwnerKey = @"IBFilesOwner";
static NSString* const kIBFirstResponderKey = @"IBFirstResponder";


static inline uint32_t decodeVariableLengthInteger(void const** pp);
static inline uint8_t decodeByte(void const** pp);
static inline uint16_t decodeShort(void const** pp);
static inline uint32_t decodeInt32(void const** pp);
static inline float decodeFloat32(void const** p);
static inline double decodeFloat64(void const** pp);


@interface UINibArchiveDataV1 : NSObject 
- (id) initWithData:(NSData*)data;
@end


@interface UINibArchiveDecoderV1 : NSCoder

- (id) initWithNibArchiveData:(UINibArchiveDataV1*)archiveData bundle:(NSBundle*)bundle owner:(id)owner externalObjects:(NSDictionary*)externalObjects;

- (UINibDecoderValueEntry*) _nextGenericValue;
- (UINibDecoderValueEntry*) _valueEntryForKey:(NSString*)key;

- (uint32_t) _extractInt32FromValue:(UINibDecoderValueEntry*)value;
- (uint64_t) _extractInt64FromValue:(UINibDecoderValueEntry*)value;
- (float) _extractFloat32FromValue:(UINibDecoderValueEntry*)value;
- (double) _extractFloat64FromValue:(UINibDecoderValueEntry*)value;
- (id) _extractObjectFromValue:(UINibDecoderValueEntry*)value;
- (CGRect) _extractCGRectFromValue:(UINibDecoderValueEntry*)value;
- (CGPoint) _extractCGPointFromValue:(UINibDecoderValueEntry*)value;
- (CGSize) _extractCGSizeFromValue:(UINibDecoderValueEntry*)value;
- (UIEdgeInsets) _extractUIEdgeInsetsFromValue:(UINibDecoderValueEntry*)value;

- (void) _cannotDecodeObjCType:(const char *)objcType;
- (void) _cannotDecodeType:(NSInteger)type asObjCType:(char const*)objcType;

@end


@implementation UINibDecoderForNibArchiveV1 {
    UINibArchiveDataV1* archiveData_;
}


- (id) initWithData:(NSData*)data encoderVersion:(NSUInteger)encoderVersion
{
    assert(data);
    if (nil != (self = [super init])) {
        archiveData_ = [[UINibArchiveDataV1 alloc] initWithData:data];
        if (!archiveData_) {
            return nil;
        }
    }
    return self;
}

- (NSCoder*) instantiateCoderWithBundle:(NSBundle*)bundle owner:(id)owner externalObjects:(NSDictionary*)externalObjects
{
    return [[UINibArchiveDecoderV1 alloc] initWithNibArchiveData:archiveData_ bundle:bundle owner:owner externalObjects:externalObjects];
}

@end


@implementation UINibArchiveDataV1 {
@public
    NSData* data_;
    
    uint32_t numberOfObjects;
    UINibDecoderObjectEntry* objects;
    
    uint32_t numberOfKeys;
    NSMutableArray* keys;
    uint32_t keyForInlinedValue;
    uint32_t keyForEmpty;
    
    uint32_t numberOfValues;
    UINibDecoderValueEntry* values;
    
    uint32_t numberOfClasses;
    NSMutableArray* classes;
}

- (void) dealloc
{
    if (objects) {
        free(objects);
    }
    if (values) {
        free(values);
    }
}

- (id) initWithData:(NSData*)data
{
    assert(data);
    if (nil != (self = [super init])) {
        data_ = data;
        
        /*  Is the data large enough to accommodate the header?
         */
        NSUInteger length = [data length];
        if (length <= 0x32) {
            return nil;
        }
        void const* base = [data bytes];

        /*  How many entries are in each of the four tables?  Is there at 
         *  least one item per table?
         */
        numberOfObjects = OSReadLittleInt32(base, 0x12);
        numberOfKeys = OSReadLittleInt32(base, 0x1A);
        numberOfValues = OSReadLittleInt32(base, 0x22);
        numberOfClasses = OSReadLittleInt32(base, 0x2A);
        if (!numberOfObjects
         || !numberOfKeys
         || !numberOfValues
         || !numberOfClasses
        ) {
            return nil;
        }
        
        /*  At what offset do each of the four tables start?  Are they within
         *  the bounds of the data we've been given?
         */
        uint32_t offsetOfObjects = OSReadLittleInt32(base, 0x16);
        uint32_t offsetOfKeys = OSReadLittleInt32(base, 0x1E);
        uint32_t offsetOfValues = OSReadLittleInt32(base, 0x26);
        uint32_t offsetOfClasses = OSReadLittleInt32(base, 0x2E);
        if ((offsetOfObjects >= length)
         || (offsetOfKeys >= length)
         || (offsetOfValues >= length)
         || (offsetOfClasses >= length)
        ) {
            return nil;
        }
        
        /*  Read in the object-template table.
         */
        objects = malloc(sizeof(UINibDecoderObjectEntry) * numberOfObjects);
        if (!objects) {
            return nil;
        }
        void const* op = base + offsetOfObjects;
        for (UINibDecoderObjectEntry* entry = objects, *lastEntry = entry + (numberOfObjects - 1); entry <= lastEntry; entry++) {
            uint32_t indexOfClass = decodeVariableLengthInteger(&op);
            uint32_t indexOfFirstValue = decodeVariableLengthInteger(&op);
            uint32_t count = decodeVariableLengthInteger(&op);
            
            if ((indexOfClass > numberOfClasses)
             || (indexOfFirstValue > numberOfValues)
             || ((indexOfFirstValue + count) > numberOfValues)
            ) {
                return nil;
            }
            
            entry->indexOfClass = indexOfClass;
            entry->indexOfFirstValue = indexOfFirstValue;
            entry->numberOfValues = count;
        }
        
        /*  Read in the keys table.
         */
        keys = [[NSMutableArray alloc] initWithCapacity:numberOfKeys];
        if (!keys) {
            return nil;
        }
        void const* kp = base + offsetOfKeys;
        static char kNSInlinedValueKey[] = "NSInlinedValue";
        static char kUINibEncoderEmptyKey[] = "UINibEncoderEmptyKey";
        for (NSUInteger i = 0, iMax = numberOfKeys; i < iMax; i++) {
            NSUInteger length = decodeVariableLengthInteger(&kp);
            NSString* key = [[NSString alloc] initWithBytes:kp length:length encoding:NSUTF8StringEncoding];
            if (!key) {
                return nil;
            }
            if (length == (sizeof(kNSInlinedValueKey)-1) && 0 == memcmp(kNSInlinedValueKey, kp, length)) {
                keyForInlinedValue = i;
            } else if (length == (sizeof(kUINibEncoderEmptyKey)-1) && 0 == memcmp(kUINibEncoderEmptyKey, kp, length)) {
                keyForEmpty = i;
            }
            [keys addObject:key];
            kp += length;
        }
        
        /*  Read in the values table.
         */
        values = malloc(sizeof(UINibDecoderValueEntry) * numberOfValues);
        if (!values) {
            return nil;
        }
        void const* vp = base + offsetOfValues;
        for (UINibDecoderValueEntry* entry = values, *lastEntry = entry + (numberOfValues - 1); entry <= lastEntry; entry++) {
            uint32_t indexOfKey = decodeVariableLengthInteger(&vp);
            if (indexOfKey > numberOfKeys) {
                return nil;
            }
            void const* data = NULL;
            uint8_t type = decodeByte(&vp);
            switch (type) {
                case kValueTypeByte: {
                    data = vp;
                    vp += 1;
                    break;
                }
                    
                case kValueTypeShort: {
                    data = vp;
                    vp += 2;
                    break;
                }
                
                case kValueTypeConstantEqualsZero:
                case kValueTypeConstantEqualsOne: {
                    /*  No additional storage  */
                    break;
                }
                    
                case kValueTypeData: {
                    data = vp;
                    uint32_t lengthOfData = decodeVariableLengthInteger(&vp);
                    vp += lengthOfData;
                    break;
                }
                    
                case kValueTypeFloat32: {
                    data = vp;
                    decodeFloat32(&vp);
                    break;
                }
                    
                case kValueTypeFloat64: {
                    data = vp;
                    decodeFloat64(&vp);
                    break;
                }
                
                case kValueTypeNull: {
                    break;
                }
                    
                case kValueTypeObject: {
                    data = vp;
                    uint32_t indexOfObject = decodeInt32(&vp);
                    if (indexOfObject > numberOfObjects) {
                        return nil;
                    }
                    break;
                }
                    
                default: {
                    NSLog(@"%@ - Unknown type code value 0x%02x; Unable to proceed.", [self class], type);
                    return nil;
                }
            }
            
            entry->indexOfKey = indexOfKey;
            entry->type = type;
            entry->data = data;
        }
        
        /*  Read in the classes table.
         */
        classes = [[NSMutableArray alloc] initWithCapacity:numberOfClasses];
        if (!classes) {
            return nil;
        }
        void const* cp = base + offsetOfClasses;
        for (NSUInteger i = 0, iMax = numberOfClasses; i < iMax; i++) {
            NSUInteger length = decodeVariableLengthInteger(&cp);
            NSUInteger unknownValue = decodeVariableLengthInteger(&cp);
            #pragma unused (unknownValue)
            NSString* className = [[NSString alloc] initWithBytes:cp length:length - 1 encoding:NSUTF8StringEncoding];
            if (!className) {
                return nil;
            }
            Class class = NSClassFromString(className);
            if (!class) {
                [self _throwCannotInstantiateClassWithName:className];
            }
            [classes addObject:class];
            cp += length;
        }
    }
    return self;
}

- (void) _throwCannotInstantiateClassWithName:(NSString*)name
{
    [NSException raise:NSInvalidUnarchiveOperationException format:@"Could not instantiate class named %@", name];
}

@end


@implementation UINibArchiveDecoderV1 {
    UINibArchiveDataV1* archiveData_;
    NSPointerArray* objects_;
    /**/
    NSBundle* bundle_;
    id owner_;
    NSDictionary* externalObjects_;
    /**/
    UINibDecoderObjectEntry* objectEntry_;
    UINibDecoderValueEntry* nextGenericValue_;
    UINibDecoderValueEntry* lastValue_;
}

static Class kClassForNSArray;
static Class kClassForNSMutableArray;
static Class kClassForNSSet;
static Class kClassForNSMutableSet;
static Class kClassForNSDictionary;
static Class kClassForNSDMutableDictionary;
static Class kClassForNSNumber;
static Class kClassForUIProxyObject;
static Class kClassForUIImageNibPlaceholder;

+ (void) initialize
{
    if (self == [UINibArchiveDecoderV1 class]) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            kClassForNSArray = NSClassFromString(@"NSArray");
            kClassForNSMutableArray = NSClassFromString(@"NSMutableArray");
            kClassForNSSet = NSClassFromString(@"NSSet");
            kClassForNSMutableSet = NSClassFromString(@"NSMutableSet");
            kClassForNSDictionary = NSClassFromString(@"NSDictionary");
            kClassForNSDMutableDictionary = NSClassFromString(@"NSMutableDictionary");
            kClassForNSNumber = NSClassFromString(@"NSNumber");
            kClassForUIProxyObject = NSClassFromString(@"UIProxyObject");
            kClassForUIImageNibPlaceholder = NSClassFromString(@"UIImageNibPlaceholder");
        });
    }
    assert(kClassForNSArray);
    assert(kClassForNSMutableArray);
    assert(kClassForNSSet);
    assert(kClassForNSMutableSet);
    assert(kClassForNSDictionary);
    assert(kClassForNSDMutableDictionary);
    assert(kClassForNSNumber);
    assert(kClassForUIProxyObject);
    assert(kClassForUIImageNibPlaceholder);
}


- (id) initWithNibArchiveData:(UINibArchiveDataV1*)archiveData bundle:(NSBundle*)bundle owner:(id)owner externalObjects:(NSDictionary*)externalObjects;
{
    assert(archiveData);
    assert(owner);
    if (nil != (self = [super init])) {
        archiveData_ = archiveData;
        bundle_ = bundle;
        owner_ = owner;
        externalObjects_ = externalObjects;
        
        objectEntry_ = archiveData_->objects;
        nextGenericValue_ = archiveData_->values + objectEntry_->indexOfFirstValue;
        lastValue_ = nextGenericValue_ + (objectEntry_->numberOfValues - 1);
        
        objects_ = [NSPointerArray pointerArrayWithStrongObjects];
        [objects_ setCount:archiveData_->numberOfObjects];
    }
    return self;
}

- (BOOL) allowsKeyedCoding
{
    return YES;
}

- (BOOL) containsValueForKey:(NSString*)key
{
    assert(key);
    return NULL != [self _valueEntryForKey:key];
}

- (const uint8_t*) decodeBytesForKey:(NSString*)key returnedLength:(NSUInteger*)lengthp
{
    UINibDecoderValueEntry* value = [self _valueEntryForKey:key];
    if (!value || value->type != kValueTypeData) {
        return NULL;
    }
    void const* vp = value->data;
    NSUInteger lengthOfData = decodeVariableLengthInteger(&vp);
    *lengthp = lengthOfData;
    return lengthOfData ? vp : NULL;
}

- (id) decodeObjectForKey:(NSString*)key
{
    assert(key);
    UINibDecoderValueEntry* value = [self _valueEntryForKey:key];
    if (!value) {
        return nil;
    }
    return [self _extractObjectFromValue:value];
}

- (BOOL) decodeBoolForKey:(NSString*)key
{
    assert(key);
    UINibDecoderValueEntry* value = [self _valueEntryForKey:key];
    if (!value) {
        return NO;
    }
    return [self _extractInt32FromValue:value];
}

- (int) decodeIntForKey:(NSString*)key
{
    assert(key);
    UINibDecoderValueEntry* value = [self _valueEntryForKey:key];
    if (!value) {
        return NO;
    }
    return [self _extractInt32FromValue:value];
}

- (NSInteger) decodeIntegerForKey:(NSString*)key
{
    assert(key);
    UINibDecoderValueEntry* value = [self _valueEntryForKey:key];
    if (!value) {
        return NO;
    }
#if __LP64__ || (TARGET_OS_EMBEDDED && !TARGET_OS_IPHONE)
    return [self _extractInt64FromValue:value];
#else
    return [self _extractInt32FromValue:value];
#endif
}

- (int32_t) decodeInt32ForKey:(NSString*)key
{
    assert(key);
    UINibDecoderValueEntry* value = [self _valueEntryForKey:key];
    if (!value) {
        return NO;
    }
    return [self _extractInt32FromValue:value];
}

- (int64_t) decodeInt64ForKey:(NSString*)key
{
    assert(key);
    UINibDecoderValueEntry* value = [self _valueEntryForKey:key];
    if (!value) {
        return NO;
    }
    return [self _extractInt64FromValue:value];
}

- (float) decodeFloatForKey:(NSString*)key
{
    assert(key);
    UINibDecoderValueEntry* value = [self _valueEntryForKey:key];
    if (!value) {
        return NO;
    }
    return [self _extractFloat32FromValue:value];
}

- (double) decodeDoubleForKey:(NSString*)key
{
    assert(key);
    UINibDecoderValueEntry* value = [self _valueEntryForKey:key];
    if (!value) {
        return NO;
    }
    return [self _extractFloat64FromValue:value];
}

- (CGRect) decodeCGRectForKey:(NSString*)key
{
    assert(key);
    UINibDecoderValueEntry* value = [self _valueEntryForKey:key];
    if (!value) {
        return CGRectZero;
    }
    return [self _extractCGRectFromValue:value];
}

- (CGPoint) decodeCGPointForKey:(NSString*)key
{
    assert(key);
    UINibDecoderValueEntry* value = [self _valueEntryForKey:key];
    if (!value) {
        return CGPointZero;
    }
    return [self _extractCGPointFromValue:value];
}

- (CGSize) decodeCGSizeForKey:(NSString*)key
{
    assert(key);
    UINibDecoderValueEntry* value = [self _valueEntryForKey:key];
    if (!value) {
        return CGSizeZero;
    }
    return [self _extractCGSizeFromValue:value];
}

- (UIEdgeInsets) decodeUIEdgeInsetsForKey:(NSString*)key
{
    assert(key);
    UINibDecoderValueEntry* value = [self _valueEntryForKey:key];
    if (!value) {
        return UIEdgeInsetsZero;
    }
    return [self _extractUIEdgeInsetsFromValue:value];
}

- (NSString*) description
{
    NSMutableString* s = [[NSMutableString alloc] init];
    [s appendFormat:@"<%@:%p class=%@, %ld values:{", NSStringFromClass([self class]), self, NSStringFromClass(archiveData_->classes[objectEntry_->indexOfClass]), objectEntry_->numberOfValues];
    UINibDecoderValueEntry* value = archiveData_->values + objectEntry_->indexOfFirstValue;
    UINibDecoderValueEntry* lastValue = value + (objectEntry_->numberOfValues - 1);
    while (value <= lastValue) {
        [s appendFormat:@"\n  %@ == %@", [archiveData_->keys objectAtIndex:value->indexOfKey], [self _extractObjectFromValue:value]];
        value++;
    }
    if (objectEntry_->numberOfValues) {
        [s appendString:@"\n"];
    }
    [s appendString:@"}>"];
    return s;
}


#pragma mark

- (UINibDecoderValueEntry*) _nextGenericValue
{
    UINibDecoderValueEntry* value = NULL;
    while (nextGenericValue_ <= lastValue_) {
        uint32_t indexOfKey = nextGenericValue_->indexOfKey;
        if (indexOfKey == archiveData_->keyForInlinedValue || indexOfKey == archiveData_->keyForEmpty) {
            value = nextGenericValue_;
            nextGenericValue_++;
            break;
        }
        nextGenericValue_++;
    }
    return value;
}

- (UINibDecoderValueEntry*) _valueEntryForKey:(NSString*)key
{
    assert(key);
    NSArray* keys = archiveData_->keys;
    for (UINibDecoderValueEntry* value = archiveData_->values + objectEntry_->indexOfFirstValue; value <= lastValue_; value++) {
        assert(value->indexOfKey < archiveData_->numberOfValues);
        NSString* keyToTest = [keys objectAtIndex:value->indexOfKey];
        if ([keyToTest isEqualToString:key]) {
            return value;
        }
    }
    return NULL;
}

- (uint32_t) _extractInt32FromValue:(UINibDecoderValueEntry*)value
{
    void const* vp = value->data;
    switch (value->type) {
        case kValueTypeConstantEqualsZero: {
            return 0;
        }
            
        case kValueTypeConstantEqualsOne: {
            return 1;
        }
            
        case kValueTypeByte: {
            return decodeByte(&vp);
        }
            
        case kValueTypeShort: {
            return decodeShort(&vp);
        }
    }

    [self _cannotDecodeType:value->type asObjCType:"i"];
    return 0;
}

- (uint64_t) _extractInt64FromValue:(UINibDecoderValueEntry*)value
{
    void const* vp = value->data;
    switch (value->type) {
        case kValueTypeConstantEqualsZero: {
            return 0;
        }
            
        case kValueTypeConstantEqualsOne: {
            return 1;
        }
            
        case kValueTypeByte: {
            return decodeByte(&vp);
        }

        case kValueTypeShort: {
            return decodeShort(&vp);
        }
    }
    
    [self _cannotDecodeType:value->type asObjCType:"i"];
    return 0;
}

- (float) _extractFloat32FromValue:(UINibDecoderValueEntry*)value
{
    void const* vp = value->data;
    switch (value->type) {
        case kValueTypeConstantEqualsZero: {
            return 0.0f;
        }
            
        case kValueTypeConstantEqualsOne: {
            return 1.0f;
        }
            
        case kValueTypeByte: {
            return decodeByte(&vp);
        }
            
        case kValueTypeShort: {
            return decodeShort(&vp);
        }
            
        case kValueTypeFloat32: {
            return decodeFloat32(&vp);
        }

        case kValueTypeFloat64: {
            return decodeFloat64(&vp);
        }
    }
    
    [self _cannotDecodeType:value->type asObjCType:"f"];
    return 0;
}

- (double) _extractFloat64FromValue:(UINibDecoderValueEntry*)value
{
    void const* vp = value->data;
    switch (value->type) {
        case kValueTypeConstantEqualsZero: {
            return 0.0;
        }
            
        case kValueTypeConstantEqualsOne: {
            return 1.0;
        }
            
        case kValueTypeByte: {
            return decodeByte(&vp);
        }
            
        case kValueTypeShort: {
            return decodeShort(&vp);
        }
            
        case kValueTypeFloat32: {
            return decodeFloat32(&vp);
        }
            
        case kValueTypeFloat64: {
            return decodeFloat64(&vp);
        }
    }
    
    [self _cannotDecodeType:value->type asObjCType:"d"];
    return 0;
}

- (id) _extractObjectFromValue:(UINibDecoderValueEntry*)value
{
    void const* vp = value->data;
    switch (value->type) {
        case kValueTypeObject: {
            uint32_t indexOfObject = decodeInt32(&vp);
            id object = [objects_ pointerAtIndex:indexOfObject];
            if (!object) {
                UINibDecoderObjectEntry* objectEntry = archiveData_->objects + indexOfObject;
                Class class = archiveData_->classes[objectEntry->indexOfClass];
                UINibDecoderValueEntry* value = archiveData_->values + objectEntry->indexOfFirstValue;
                UINibDecoderValueEntry* lastValue = value + (objectEntry->numberOfValues - 1);
                if (class == kClassForNSArray || class == kClassForNSMutableArray) {
                    assert(value->indexOfKey == archiveData_->keyForInlinedValue);
                    assert(value->type == kInlinedValueTypeArray);
                    value++;
                    NSMutableArray* array = [[NSMutableArray alloc] initWithCapacity:objectEntry->numberOfValues - 1];
                    while (value <= lastValue) {
                        id object = [self _extractObjectFromValue:value++];
                        [array addObject:object];
                    }
                    object = array;
                } else if (class == kClassForNSSet || class == kClassForNSMutableSet) {
                    assert(value->indexOfKey == archiveData_->keyForInlinedValue);
                    assert(value->type == kInlinedValueTypeArray);
                    value++;
                    NSMutableSet* set = [[NSMutableSet alloc] initWithCapacity:objectEntry->numberOfValues - 1];
                    while (value <= lastValue) {
                        id object = [self _extractObjectFromValue:value++];
                        [set addObject:object];
                    }
                    object = set;
                } else if (class == kClassForNSDictionary || class == kClassForNSDMutableDictionary) {
                    assert(value->indexOfKey == archiveData_->keyForInlinedValue);
                    assert(value->type == kInlinedValueTypeArray);
                    assert(((objectEntry->numberOfValues - 1) & 1) == 0); // Should be an even number of keys and values, right?
                    NSUInteger numberOfEntries = ((objectEntry->numberOfValues - 1) >> 1);
                    value++;
                    NSMutableDictionary* dict = [[NSMutableDictionary alloc] initWithCapacity:objectEntry->numberOfValues - 1];
                    while (numberOfEntries--) {
                        assert(value->indexOfKey == archiveData_->keyForEmpty);
                        id k = [self _extractObjectFromValue:value++];
                        assert(value->indexOfKey == archiveData_->keyForEmpty);
                        id v = [self _extractObjectFromValue:value++];
                        [dict setObject:v forKey:k];
                    }
                    object = dict;
                } else if (class == kClassForNSNumber) {
                    return [self _extractObjectFromValue:value];
                } else {
                    UINibDecoderObjectEntry* myObjectEntry = objectEntry_;
                    UINibDecoderValueEntry* myNextGenericValue = nextGenericValue_;
                    UINibDecoderValueEntry* myLastValue = lastValue_;
                    
                    objectEntry_ = objectEntry;
                    nextGenericValue_ = value;
                    lastValue_ = lastValue;
                    
                    object = [[class alloc] initWithCoder:self];
                    
                    objectEntry_ = myObjectEntry;
                    nextGenericValue_ = myNextGenericValue;
                    lastValue_ = myLastValue;
                }

                assert(object);
                [object awakeAfterUsingCoder:self];
                
                if (class == kClassForUIProxyObject) {
                    NSString* proxiedObjectIdentifier = [object proxiedObjectIdentifier];
                    if ([proxiedObjectIdentifier isEqualToString:kIBFilesOwnerKey]) {
                        object = owner_; 
                    } else if ([proxiedObjectIdentifier isEqualToString:kIBFirstResponderKey]) {
                        object = [NSNull null];
                    } else {
                        object = [externalObjects_ objectForKey:proxiedObjectIdentifier];
                    }
                    if (!object) {
                        [self _cannotDereferenceExternalObject:proxiedObjectIdentifier];
                    }
                } else if (class == kClassForUIImageNibPlaceholder) {
                    NSString* resourceName = [object resourceName];
                    object = [UIImage imageWithContentsOfFile:[bundle_ pathForResource:resourceName ofType:nil]];
                }

                [objects_ replacePointerAtIndex:indexOfObject withPointer:(__bridge void *)(object)];
            }
            return object;
        }
            
        case kValueTypeNull: {
            return nil;
        }
            
        case kValueTypeByte: {
            uint8_t v = decodeByte(&vp);
            return @(v);
        }
            
        case kValueTypeShort: {
            uint16_t v = decodeShort(&vp);
            return @(v);
        }
            
        case kValueTypeConstantEqualsZero: {
            return @(0);
        }
            
        case kValueTypeConstantEqualsOne: {
            return @(1);
        }

        case kValueTypeFloat32: {
            float v = decodeFloat32(&vp);
            return @(v);
        }

        case kValueTypeFloat64: {
            float v = decodeFloat64(&vp);
            return @(v);
        }

        case kValueTypeData: {
            uint32_t lengthOfData = decodeVariableLengthInteger(&vp);
            return [[NSData alloc] initWithBytes:vp length:lengthOfData];
        }
    }

    [self _cannotDecodeType:value->type asObjCType:"@"];
    return nil;
}

- (CGRect) _extractCGRectFromValue:(UINibDecoderValueEntry*)value
{
    void const* vp = value->data;
    switch (value->type) {
        case kValueTypeData: {
            uint32_t lengthOfData = decodeVariableLengthInteger(&vp);
            if (lengthOfData != 0x11) {
                break;
            }
            
            switch (decodeByte(&vp)) {
                case kValueTypeFloat32: {
                    CGFloat x = decodeFloat32(&vp);
                    CGFloat y = decodeFloat32(&vp);
                    CGFloat w = decodeFloat32(&vp);
                    CGFloat h = decodeFloat32(&vp);
                    return CGRectMake(x, y, w, h);
                }
                    
                case kValueTypeFloat64: {
                    CGFloat x = decodeFloat64(&vp);
                    CGFloat y = decodeFloat64(&vp);
                    CGFloat w = decodeFloat64(&vp);
                    CGFloat h = decodeFloat64(&vp);
                    return CGRectMake(x, y, w, h);
                }
            }
        }
    }
    
    [self _cannotDecodeType:value->type asObjCType:"CGRect"];
    return CGRectZero;
}

- (CGPoint) _extractCGPointFromValue:(UINibDecoderValueEntry*)value
{
    void const* vp = value->data;
    switch (value->type) {
        case kValueTypeData: {
            uint32_t lengthOfData = decodeVariableLengthInteger(&vp);
            if (lengthOfData != 0x09) {
                break;
            }
            
            switch (decodeByte(&vp)) {
                case kValueTypeFloat32: {
                    CGFloat x = decodeFloat32(&vp);
                    CGFloat y = decodeFloat32(&vp);
                    return CGPointMake(x, y);
                }
                    
                case kValueTypeFloat64: {
                    CGFloat x = decodeFloat64(&vp);
                    CGFloat y = decodeFloat64(&vp);
                    return CGPointMake(x, y);
                }
            }
        }
    }
    
    [self _cannotDecodeType:value->type asObjCType:"CGPoint"];
    return CGPointZero;
}

- (CGSize) _extractCGSizeFromValue:(UINibDecoderValueEntry*)value
{
    void const* vp = value->data;
    switch (value->type) {
        case kValueTypeData: {
            uint32_t lengthOfData = decodeVariableLengthInteger(&vp);
            if (lengthOfData != 0x09) {
                break;
            }
            
            switch (decodeByte(&vp)) {
                case kValueTypeFloat32: {
                    CGFloat w = decodeFloat32(&vp);
                    CGFloat h = decodeFloat32(&vp);
                    return CGSizeMake(w, h);
                }
                    
                case kValueTypeFloat64: {
                    CGFloat w = decodeFloat64(&vp);
                    CGFloat h = decodeFloat64(&vp);
                    return CGSizeMake(w, h);
                }
            }
        }
    }
    
    [self _cannotDecodeType:value->type asObjCType:"CGSize"];
    return CGSizeZero;
}

- (UIEdgeInsets) _extractUIEdgeInsetsFromValue:(UINibDecoderValueEntry*)value
{
    void const* vp = value->data;
    switch (value->type) {
        case kValueTypeData: {
            uint32_t lengthOfData = decodeVariableLengthInteger(&vp);
            if (lengthOfData != 0x11) {
                break;
            }
            
            switch (decodeByte(&vp)) {
                case kValueTypeFloat32: {
                    CGFloat top = decodeFloat32(&vp);
                    CGFloat left = decodeFloat32(&vp);
                    CGFloat bottom = decodeFloat32(&vp);
                    CGFloat right = decodeFloat32(&vp);
                    return UIEdgeInsetsMake(top, left, bottom, right);
                }
                    
                case kValueTypeFloat64: {
                    CGFloat top = decodeFloat64(&vp);
                    CGFloat left = decodeFloat64(&vp);
                    CGFloat bottom = decodeFloat64(&vp);
                    CGFloat right = decodeFloat64(&vp);
                    return UIEdgeInsetsMake(top, left, bottom, right);
                }
            }
        }
    }
    
    [self _cannotDecodeType:value->type asObjCType:"UIEdgeInsets"];
    return UIEdgeInsetsZero;
}

- (void) _cannotDereferenceExternalObject:(NSString*)identifier
{
    [NSException raise:[self className] format:@"Unable to load Nib: Unable to deference external object \"%@\"", identifier];
}

- (void) _cannotDecodeObjCType:(const char *)objcType 
{
    [NSException raise:[self className] format:@"Unable to load Nib: Unknown Objc-Type \"%s\"", objcType];
}

- (void) _cannotDecodeType:(NSInteger)type asObjCType:(char const*)objcType 
{
    [NSException raise:[self className] format:@"Unable to load Nib: Cannot decode type-code %ld as %s", type, objcType];
}

@end



uint32_t decodeVariableLengthInteger(void const** pp)
{
    uint8_t const* p = *pp;
    uint8_t c = *p++;
    uint32_t v = c & 0x7F;
    if (0 == (c & 0x80)) {
        uint32_t shift = 7;
        do {
            c = *p++;
            v |= (c & 0x7F) << shift;
            shift += 7;
        } while (0 == (c & 0x80));
    }
    *pp = p;
    return v;
}

uint8_t decodeByte(void const** pp)
{
    uint8_t const* p = *pp;
    uint8_t v = *p++;
    *pp = p;
    return v;
}

uint16_t decodeShort(void const** pp)
{
    uint16_t v = OSReadLittleInt16(*pp, 0);
    *pp += 2;
    return v;
}

uint32_t decodeInt32(void const** pp) 
{
    uint32_t v = OSReadLittleInt32(*pp, 0);
    *pp += 4;
    return v;
}

float decodeFloat32(void const** pp)
{
    uint32_t v = OSReadLittleInt32(*pp, 0);
    *pp += 4;
    return *(float*)&v;
}

double decodeFloat64(void const** pp)
{
    uint64_t v = OSReadLittleInt64(*pp, 0);
    *pp += 8;
    return *(double*)&v;
}

