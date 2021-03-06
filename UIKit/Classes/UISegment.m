#import "UISegment.h"

static NSString* const kUISegmentInfoKey = @"UISegmentInfo";
static NSString* const kUISegmentPositionKey = @"UISegmentPosition";

@implementation UISegment

- (id) initWithCoder:(NSCoder*)coder
{
    if (nil != (self = [super initWithCoder:coder])) {
        if ([coder containsValueForKey:kUISegmentInfoKey]) {
            self.title = [coder decodeObjectForKey:kUISegmentInfoKey];
        }
        if ([coder containsValueForKey:kUISegmentPositionKey]) {
            self.position = [coder decodeIntegerForKey:kUISegmentPositionKey];
        }
    }
    return self;
}

- (void) encodeWithCoder:(NSCoder*)coder
{
    [self doesNotRecognizeSelector:_cmd];
}

@end
