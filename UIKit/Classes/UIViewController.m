/*
 * Copyright (c) 2011, The Iconfactory. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * 3. Neither the name of The Iconfactory nor the names of its contributors may
 *    be used to endorse or promote products derived from this software without
 *    specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE ICONFACTORY BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 * OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "UIViewController+UIPrivate.h"
#import "UIView+UIPrivate.h"
#import "UIScreen.h"
#import "UIWindow.h"
#import "UIScreen.h"
#import "UINavigationItem.h"
#import "UIBarButtonItem.h"
#import "UINavigationController.h"
#import "UISplitViewController.h"
#import "UIToolbar.h"
#import "UIScreen.h"
#import "UITabBarController.h"
#import "UINib.h"
#import "UINibLoading.h"
#import "UIStoryboard.h"
#import "UIStoryboard+UIPrivate.h"
#import "UIStoryboardSegueTemplate.h"
#import "UIStoryboardSegue.h"


static NSString* const kUIExternalObjectsTableForViewLoadingKey = @"UIExternalObjectsTableForViewLoading";
static NSString* const kUINibNameKey                            = @"UINibName";
static NSString* const kUIStoryboardSegueTemplatesKey           = @"UIStoryboardSegueTemplates";


@interface UIViewController ()
@property (nonatomic, readonly) NSArray* storyboardSegueTemplates;
@end


@implementation UIViewController {
    NSString* _storyboardIdentifier;
    NSString* _topLevelObjectsToKeepAliveFromStoryboard;

    UIViewControllerAppearState _appearState;
    
    struct {
        BOOL wantsFullScreenLayout : 1;
        BOOL modalInPopover : 1;
        BOOL editing : 1;
        BOOL hidesBottomBarWhenPushed : 1;
        BOOL isInAnimatedVCTransition : 1;
        BOOL viewLoadedFromControllerNib : 1;
    } _flags;
}
@synthesize navigationItem = _navigationItem;
@synthesize view = _view;

- (id)init
{
#pragma mark - @@@BP Added
    _childViewControllers = [NSMutableArray new];
#pragma mark -
    
    NSBundle* bundle = [NSBundle bundleForClass:[self class]];
    NSString* nibPath = [bundle pathForResource:NSStringFromClass([self class]) ofType:@"nib"];
    if (nibPath && bundle) {
        return [self initWithNibName:NSStringFromClass([self class]) bundle:bundle];
    } else {
        return [self initWithNibName:nil bundle:nil];
    }
}

- (id)initWithNibName:(NSString *)nibName bundle:(NSBundle *)nibBundle
{
    if (nil != (self = [super init])) {
        _nibName = [nibName copy];
        _nibBundle = nibBundle;
        _contentSizeForViewInPopover = CGSizeMake(320,1100);
    }
    return self;
}

- (id) initWithCoder:(NSCoder*)coder
{
    if (nil != (self = [super init])) {
        if ([coder containsValueForKey:kUINibNameKey]) {
            _storyboardIdentifier = [[coder decodeObjectForKey:kUINibNameKey] copy];
        }
        if ([coder containsValueForKey:kUIExternalObjectsTableForViewLoadingKey]) {
            _topLevelObjectsToKeepAliveFromStoryboard = [coder decodeObjectForKey:kUIExternalObjectsTableForViewLoadingKey];
        }
        if ([coder containsValueForKey:kUIStoryboardSegueTemplatesKey]) {
            _storyboardSegueTemplates = [coder decodeObjectForKey:kUIStoryboardSegueTemplatesKey];
        }
    }
    return self;
}

- (void) encodeWithCoder:(NSCoder *)aCoder
{
    [self doesNotRecognizeSelector:_cmd];
}

- (void)dealloc
{
    [_view _setViewController:nil];
}

- (UIResponder *)nextResponder
{
    return _view.superview;
}

- (BOOL) isModalInPopover
{
    return _flags.modalInPopover;
}

- (void) setModalInPopover:(BOOL)modalInPopover
{
    _flags.modalInPopover = modalInPopover;
}

- (BOOL) wantsFullScreenLayout
{
    return _flags.wantsFullScreenLayout;
}

- (void) setWantsFullScreenLayout:(BOOL)wantsFullScreenLayout
{
    _flags.wantsFullScreenLayout = wantsFullScreenLayout;
}

- (BOOL) hidesBottomBarWhenPushed
{
    return _flags.hidesBottomBarWhenPushed;
}

- (void) setHidesBottomBarWhenPushed:(BOOL)hidesBottomBarWhenPushed
{
    _flags.hidesBottomBarWhenPushed = hidesBottomBarWhenPushed;
}

- (BOOL)isViewLoaded
{
    return (_view != nil);
}

- (UIView *)view
{
    if (!_flags.viewLoadedFromControllerNib) {
        _flags.viewLoadedFromControllerNib = YES;
        [self loadView];
        [self viewDidLoad];
    }
    return _view;
}

- (void)setView:(UIView *)aView
{
    if (aView != _view) {
        [_view _setViewController:nil];
        _view = aView;
        [_view _setViewController:self];
    }
}

- (void)loadView
{
    if (self.storyboard) {
        [[self.storyboard nibForStoryboardNibNamed:_storyboardIdentifier] instantiateWithOwner:self options:@{
            UINibExternalObjects: _topLevelObjectsToKeepAliveFromStoryboard,
        }];
    } else if (self.nibName) {
        [[UINib nibWithNibName:self.nibName bundle:self.nibBundle] instantiateWithOwner:self options:nil];
    } else {
        self.view = [[UIView alloc] initWithFrame:CGRectMake(0,0,320,480)];
    }
}

- (void)viewDidLoad
{
}

- (void)viewDidUnload
{
}

- (void)didReceiveMemoryWarning
{
}

- (void)viewWillAppear:(BOOL)animated
{
}

- (void)viewDidAppear:(BOOL)animated
{
}

- (void)viewWillDisappear:(BOOL)animated
{
}

- (void)viewDidDisappear:(BOOL)animated
{
}

- (void)viewWillLayoutSubviews
{
}

- (void)viewDidLayoutSubviews
{
}

- (UIInterfaceOrientation)interfaceOrientation
{
    return (UIInterfaceOrientation) UIDeviceOrientationPortrait;
}

- (UINavigationItem *)navigationItem
{
    if (!_navigationItem) {
        _navigationItem = [[UINavigationItem alloc] initWithTitle:self.title];
    }
    return _navigationItem;
}

- (void)_setParentViewController:(UIViewController *)parentController
{
    _parentViewController = parentController;
}

- (void)setToolbarItems:(NSArray *)theToolbarItems animated:(BOOL)animated
{
    if (_toolbarItems != theToolbarItems) {
        _toolbarItems = theToolbarItems;
        [self.navigationController.toolbar setItems:_toolbarItems animated:animated];
    }
}

- (void)setToolbarItems:(NSArray *)theToolbarItems
{
    [self setToolbarItems:theToolbarItems animated:NO];
}

- (BOOL) isEditing
{
    return _flags.editing;
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    _flags.editing = editing;
}

- (void)setEditing:(BOOL)editing
{
    [self setEditing:editing animated:NO];
}

- (UIBarButtonItem *)editButtonItem
{
    // this should really return a fancy bar button item that toggles between edit/done and sends setEditing:animated: messages to this controller
    return nil;
}

- (void)presentModalViewController:(UIViewController *)modalViewController animated:(BOOL)animated
{
    if (!_modalViewController && _modalViewController != self) {
        _modalViewController = modalViewController;
        [_modalViewController _setParentViewController:self];

        UIWindow *window = self.view.window;
        UIView *selfView = self.view;
        UIView *newView = _modalViewController.view;

        newView.autoresizingMask = selfView.autoresizingMask;
        newView.frame = _flags.wantsFullScreenLayout? window.screen.bounds : window.screen.applicationFrame;

        [window addSubview:newView];
        [_modalViewController viewWillAppear:animated];

        [self viewWillDisappear:animated];
        selfView.hidden = YES;		// I think the real one may actually remove it, which would mean needing to remember the superview, I guess? Not sure...
        [self viewDidDisappear:animated];


        [_modalViewController viewDidAppear:animated];
    }
}

#pragma mark - @@@BP
- (void)presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)isAnimated completion:(void (^)(void))completion
{
    [self presentModalViewController:viewControllerToPresent animated:isAnimated];
    dispatch_async(dispatch_get_main_queue(), completion);
}

- (void)dismissViewControllerAnimated:(BOOL)isAnimated completion:(void (^)(void))completion
{
    [self dismissModalViewControllerAnimated:isAnimated];
    dispatch_async(dispatch_get_main_queue(), completion);
}
#pragma mark -

- (void)dismissModalViewControllerAnimated:(BOOL)animated
{
    // NOTE: This is not implemented entirely correctly - the actual dismissModalViewController is somewhat subtle.
    // There is supposed to be a stack of modal view controllers that dismiss in a specific way,e tc.
    // The whole system of related view controllers is not really right - not just with modals, but everything else like
    // navigationController, too, which is supposed to return the nearest nav controller down the chain and it doesn't right now.

    if (_modalViewController) {
        
        // if the modalViewController being dismissed has a modalViewController of its own, then we need to go dismiss that, too.
        // otherwise things can be left hanging around.
        if (_modalViewController.modalViewController) {
            [_modalViewController dismissModalViewControllerAnimated:animated];
        }
        
        self.view.hidden = NO;
        [self viewWillAppear:animated];
        
        [_modalViewController.view removeFromSuperview];
        [_modalViewController _setParentViewController:nil];
        _modalViewController = nil;

        [self viewDidAppear:animated];
    } else {
        [self.parentViewController dismissModalViewControllerAnimated:animated];
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation duration:(NSTimeInterval)duration
{
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
}

- (void)addChildViewController:(UIViewController *)childController
{
    [childController willMoveToParentViewController:self];
    [childController _setParentViewController:self];
#pragma mark - @@@BP Added
    [self.childViewControllers addObject:childController];
#pragma mark -
}

- (void)removeFromParentViewController
{
    [self willMoveToParentViewController:nil];
    [self _setParentViewController:nil];
}

- (void)willMoveToParentViewController:(UIViewController *)parent
{
}

- (void)didMoveToParentViewController:(UIViewController *)parent
{
}

- (void)transitionFromViewController:(UIViewController *)fromViewController toViewController:(UIViewController *)toViewController duration:(NSTimeInterval)duration options:(UIViewAnimationOptions)options animations:(void (^)(void))animations completion:(void (^)(BOOL finished))completion
{
    [fromViewController beginAppearanceTransition:NO animated:duration > 0];
    [toViewController beginAppearanceTransition:YES animated:duration > 0];
    [UIView animateWithDuration:duration
        animations:^{
            [[fromViewController view] removeFromSuperview];
            [[self view] addSubview:[toViewController view]];
            if (animations) {
                animations();
            }
        }
        completion:^(BOOL finished){
            if (completion) {
                completion(finished);
            }
            [fromViewController _endAppearanceTransition];
            [toViewController _endAppearanceTransition];
        }
     ];
}

- (id)_nearestParentViewControllerThatIsKindOf:(Class)c
{
    UIViewController *controller = _parentViewController;

    while (controller && ![controller isKindOfClass:c]) {
        controller = [controller parentViewController];
    }

    return controller;
}

- (UINavigationController *)navigationController
{
    return [self _nearestParentViewControllerThatIsKindOf:[UINavigationController class]];
}

- (UISplitViewController *)splitViewController
{
    return [self _nearestParentViewControllerThatIsKindOf:[UISplitViewController class]];
}

- (void)_setViewAppearState:(UIViewControllerAppearState)appearState isAnimating:(BOOL)animating
{
    if (_appearState != appearState) {
        _appearState = appearState;
        switch (_appearState) {
            case UIViewControllerStateWillAppear: {
                [self viewWillAppear:animating];
                break;
            }
            case UIViewControllerStateDidAppear: {
                [self viewDidAppear:animating];
                break;
            } 
            case UIViewControllerStateWillDisappear: {
                [self viewWillDisappear:animating];
                break;
            }  
            case UIViewControllerStateDidDisappear: {
                [self viewDidDisappear:animating];
                break;
            }
        }
    }
}

- (void)viewWillMoveToWindow:(UIWindow *)window
{
    if (!_flags.isInAnimatedVCTransition) {
        if (window) {
            [self _setViewAppearState:UIViewControllerStateWillAppear isAnimating:NO];
        } else {
            [self _setViewAppearState:UIViewControllerStateWillDisappear isAnimating:NO];
        }
    }
}

- (void)viewDidMoveToWindow:(UIWindow *)window
{
    if (!_flags.isInAnimatedVCTransition) {
        if (window) {
            [self _setViewAppearState:UIViewControllerStateDidAppear isAnimating:NO];
        } else {
            [self _setViewAppearState:UIViewControllerStateDidDisappear isAnimating:NO];
        }
    }
}

- (BOOL)beginAppearanceTransition:(BOOL)shouldAppear animated:(BOOL)animated
{
    if (animated) {
        _flags.isInAnimatedVCTransition = YES;
        UIViewControllerAppearState appearState;
        if (shouldAppear) {
            appearState = UIViewControllerStateWillAppear;
        } else {
            appearState = UIViewControllerStateWillDisappear;
        }
        [self _setViewAppearState:appearState isAnimating:animated];
        return YES;
    }
    return NO;
}

- (BOOL)_endAppearanceTransition
{
    if (_flags.isInAnimatedVCTransition) {
        UIViewControllerAppearState appearState;
        if (_appearState == UIViewControllerStateWillAppear) {
            appearState = UIViewControllerStateDidAppear;
        } else if (_appearState == UIViewControllerStateWillDisappear) {
            appearState = UIViewControllerStateDidDisappear;
        } else {
            return NO;
        }
        [self _setViewAppearState:appearState isAnimating:NO];
        _flags.isInAnimatedVCTransition = NO;
        return YES;
    }
    return NO;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p; title = %@; view = %@>", [self className], self, self.title, self.view];
}

- (UIView *)rotatingHeaderView {
    return nil;
}

- (UIView *)rotatingFooterView {
    return nil;
}


#pragma mark Storyboard

- (void) performSegueWithIdentifier:(NSString*)identifier sender:(id)sender
{
    if (![self shouldPerformSegueWithIdentifier:identifier sender:sender]) {
        return;
    }

    UIStoryboardSegueTemplate* segueTemplate = [self _segueTemplateForIdentifier:identifier];
    if (!segueTemplate) {
        [NSException raise:NSInvalidArgumentException format:@"Receiver (%@) has no segue with identifier '%@'", self, identifier];
    }

    UIViewController* destination = [[self storyboard] instantiateViewControllerWithIdentifier:[segueTemplate destinationViewControllerIdentifier]];
    if (destination) {
        UIStoryboardSegue* segue = [segueTemplate segueWithDestinationViewController:destination];
        if (segue) {
            [self prepareForSegue:segue sender:sender];
            [segue perform];
        }
    }
}

- (BOOL) shouldPerformSegueWithIdentifier:(NSString*)identifier sender:(id)sender
{
    return YES;
}

- (void) prepareForSegue:(UIStoryboardSegue*)segue sender:(id)sender
{
}

- (UIStoryboardSegueTemplate*) _segueTemplateForIdentifier:(NSString*)identifier
{
    for (UIStoryboardSegueTemplate* segueTemplate in _storyboardSegueTemplates) {
        if ([[segueTemplate identifier] isEqualToString:identifier]) {
            return segueTemplate;
        }
    }
    return nil;
}

@end
