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

#import "UINavigationController.h"
#import "UIViewController+UIPrivate.h"
#import "UITabBarController.h"
#import "UINavigationBar.h"
#import "UIToolbar.h"

static const NSTimeInterval kAnimationDuration = 0.22;
static const CGFloat NavBarHeight = 44;
static const CGFloat ToolbarHeight = 28;

@interface UINavigationController (UIPrivate)
- (void) transitionFromViewController:(UIViewController *)fromViewController toViewController:(UIViewController *)toViewController duration:(NSTimeInterval)duration direction:(NSInteger)direction animations:(void (^)(void))animations completion:(void (^)(BOOL))completion;
@end

@implementation UINavigationController {
    UIView* _containerView;
    NSMutableArray *_viewControllers;
    
    struct {
        BOOL didShowViewController : 1;
        BOOL willShowViewController : 1;
    } _delegateHas;
}
@synthesize toolbarHidden = _toolbarHidden;

- (UIViewController *)visibleViewController
{
	return [self.viewControllers lastObject];
}

- (id)initWithNibName:(NSString *)nibName bundle:(NSBundle *)bundle
{
	if ((self=[super initWithNibName:nibName bundle:bundle])) {
		_viewControllers = [[NSMutableArray alloc] initWithCapacity:1];
		_navigationBar = [[UINavigationBar alloc] init];
		_navigationBar.delegate = self;
		_toolbar = [[UIToolbar alloc] init];
		_toolbarHidden = YES;
		_navigationBarHidden = NO;
	}
	return self;
}

- (id)initWithRootViewController:(UIViewController *)rootViewController
{
	if ((self=[self initWithNibName:nil bundle:nil])) {
		self.viewControllers = @[rootViewController];
	}
	return self;
}

#pragma mark - @@@BP Added placeholder.
- (NSObject *)initWithNavigationBarClass:(Class)navigationBarClass toolbarClass:(Class)toolbarClass
{
    self = [self initWithNibName:nil bundle:nil];
    return self;
}
#pragma mark -


- (void)setDelegate:(id<UINavigationControllerDelegate>)newDelegate
{
	_delegate = newDelegate;
	_delegateHas.didShowViewController = [_delegate respondsToSelector:@selector(navigationController:didShowViewController:animated:)];
	_delegateHas.willShowViewController = [_delegate respondsToSelector:@selector(navigationController:willShowViewController:animated:)];
}

- (CGRect)_navigationBarFrame
{
	CGRect navBarFrame = self.view.bounds;
	navBarFrame.size.height = NavBarHeight;
	return navBarFrame;
}

- (CGRect)_toolbarFrame
{
	CGRect toolbarRect = self.view.bounds;
	toolbarRect.origin.y = toolbarRect.origin.y + toolbarRect.size.height - ToolbarHeight;
	toolbarRect.size.height = ToolbarHeight;
	return toolbarRect;
}

- (CGRect)_controllerFrame
{
	CGRect controllerFrame = self.view.bounds;
    
	// adjust for the nav bar
	if (!self.navigationBarHidden) {
		controllerFrame.origin.y += NavBarHeight;
		controllerFrame.size.height -= NavBarHeight;
	}
	
	// adjust for toolbar (if there is one)
	if (!self.toolbarHidden) {
		controllerFrame.size.height -= ToolbarHeight;
	}
	
	return controllerFrame;
}

- (void)loadView
{
	self.view = [[UIView alloc] initWithFrame:CGRectMake(0,0,320,480)];
	self.view.clipsToBounds = YES;

	_navigationBar.frame = [self _navigationBarFrame];
	_navigationBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_navigationBar.hidden = self.navigationBarHidden;
	[self.view addSubview:_navigationBar];
	
	_toolbar.frame = [self _toolbarFrame];
	_toolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
	_toolbar.hidden = self.toolbarHidden;
	[self.view addSubview:_toolbar];
}

- (void)_updateToolbar:(BOOL)animated
{
	UIViewController *topController = self.topViewController;
	[_toolbar setItems:topController.toolbarItems animated:animated];
	_toolbar.hidden = self.toolbarHidden;
	_containerView.frame = [self _controllerFrame];
}

- (void)setViewControllers:(NSArray *)newViewControllers animated:(BOOL)animated
{
	assert([newViewControllers count] >= 1);
	if (newViewControllers != _viewControllers) 
	{
		UIViewController *previousTopController = self.topViewController;
        
		if (previousTopController) {
			[previousTopController.view removeFromSuperview];
		}
        
		for (UIViewController *controller in _viewControllers) {
			[controller removeFromParentViewController];
            [controller didMoveToParentViewController:nil];
		}
		
		_viewControllers = [newViewControllers mutableCopy];
		
		NSMutableArray *items = [NSMutableArray arrayWithCapacity:[_viewControllers count]];
		
		for (UIViewController *controller in _viewControllers) {
            [self addChildViewController:controller];
			[items addObject:controller.navigationItem];
		}
        
        [self transitionFromViewController:nil toViewController:self.topViewController duration:0 direction:1 animations:nil completion:^(BOOL finished){
            for (UIViewController *controller in _viewControllers) {
                [controller didMoveToParentViewController:self];
            }
        }];
        
		[_navigationBar setItems:items animated:animated];
		[self _updateToolbar:animated];
	}
}

- (void)setViewControllers:(NSArray *)newViewControllers
{
	[self setViewControllers:newViewControllers animated:NO];
}

- (UIViewController *)topViewController
{
	return [_viewControllers lastObject];
}

- (void) transitionFromViewController:(UIViewController *)fromViewController toViewController:(UIViewController *)toViewController duration:(NSTimeInterval)duration direction:(NSInteger)direction animations:(void (^)(void))animations completion:(void (^)(BOOL))completion
{
    assert(toViewController);
    const CGRect b = [self _controllerFrame];
    const CGRect c = CGRectOffset(b, direction * -b.size.width, 0);
    const CGRect a = CGRectOffset(b, direction * b.size.width, 0);

    CGRect viewFrame = {
        .size = b.size
    };
    toViewController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    toViewController.view.frame = viewFrame;
    
    UIView* oldContainerView = _containerView;
    UIView* newContainerView = [[UIView alloc] init];
#ifndef NDEBUG
    newContainerView.backgroundColor = [UIColor redColor];
#endif
    newContainerView.layer.anchorPoint = CGPointZero;
    newContainerView.frame = a;
    newContainerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [newContainerView addSubview:toViewController.view];
    _containerView = newContainerView;
    
    [self transitionFromViewController:fromViewController
        toViewController:toViewController 
        duration:duration 
        options:0 
        animations:^{
            if (animations) {
                animations();
            }
            newContainerView.frame = b;
            oldContainerView.frame = c;
        } 
        completion:^(BOOL finished){
            if (completion) {
                completion(finished);
            }
            if (fromViewController.view.superview == oldContainerView) {
                [fromViewController.view removeFromSuperview];
            }
        }
     ];
}

- (void) transitionFromViewController:(UIViewController *)fromViewController toViewController:(UIViewController *)toViewController duration:(NSTimeInterval)duration options:(UIViewAnimationOptions)options animations:(void (^)(void))animations completion:(void (^)(BOOL))completion
{
    if (self.view.window) {
        [fromViewController beginAppearanceTransition:NO animated:duration > 0];
        [toViewController beginAppearanceTransition:YES animated:duration > 0];
    }
    
    BOOL delegateHasWillShowViewController = _delegateHas.willShowViewController;
    BOOL delegateHasDidShowViewController = _delegateHas.didShowViewController;
    
    if (delegateHasWillShowViewController) {
        [_delegate navigationController:self willShowViewController:toViewController animated:duration > 0];
    }
    
    [self.view addSubview:_containerView];
    
    [UIView animateWithDuration:duration
                     animations:animations
                     completion:^(BOOL finished){
                         if (completion) {
                             completion(finished);
                         }
                         if (self.view.window) {
                             [fromViewController _endAppearanceTransition];
                             [toViewController _endAppearanceTransition];
                         }
                         if (delegateHasDidShowViewController) {
                             [_delegate navigationController:self didShowViewController:toViewController animated:duration > 0];
                         }
                     }
     ];
}

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated
{
	assert(![viewController isKindOfClass:[UITabBarController class]]);
	assert(![_viewControllers containsObject:viewController]);

    UIViewController *oldViewController = self.topViewController;
	[_viewControllers addObject:viewController];
    [self addChildViewController:viewController];

    [self transitionFromViewController:oldViewController 
        toViewController:viewController 
        duration:!animated ? 0.0 : kAnimationDuration 
        direction:1
        animations:^{
            [self _updateToolbar:animated];
            [_navigationBar pushNavigationItem:viewController.navigationItem animated:animated];
        }
        completion:^(BOOL finished){
            [viewController didMoveToParentViewController:self];
        }
    ];
}

- (UIViewController *)popViewControllerAnimated:(BOOL)animated
{
    if ([_viewControllers count] < 2) {
        return nil;
    }

    UIViewController* oldViewController = self.topViewController;
    [_viewControllers removeLastObject];
    [oldViewController removeFromParentViewController];
    UIViewController* viewController = self.topViewController;
    
    [self transitionFromViewController:oldViewController 
        toViewController:viewController 
        duration:!animated ? 0.0 : kAnimationDuration 
        direction:-1
        animations:^{
            [self _updateToolbar:animated];
            [_navigationBar popNavigationItemAnimated:animated];
        }
        completion:^(BOOL finished){
            [viewController didMoveToParentViewController:nil];
        }
    ];

    return oldViewController;
}

- (NSArray *)popToViewController:(UIViewController *)viewController animated:(BOOL)animated
{
	NSMutableArray *popped = [[NSMutableArray alloc] init];
    
	while (self.topViewController != viewController) {
		UIViewController *poppedController = [self popViewControllerAnimated:animated];
		if (poppedController) {
			[popped addObject:poppedController];
		} else {
			break;
		}
	}
	
	return popped;
}

- (NSArray *)popToRootViewControllerAnimated:(BOOL)animated
{
	return [self popToViewController:[_viewControllers objectAtIndex:0] animated:animated];
}

- (void)setToolbarHidden:(BOOL)hidden animated:(BOOL)animated
{
	_toolbarHidden = hidden;
	[self _updateToolbar:animated];
}

- (void)setToolbarHidden:(BOOL)hidden
{
	[self setToolbarHidden:hidden animated:NO];
}

- (BOOL)isToolbarHidden
{
	return _toolbarHidden || self.topViewController.hidesBottomBarWhenPushed;
}

- (void)setContentSizeForViewInPopover:(CGSize)newSize
{
	self.topViewController.contentSizeForViewInPopover = newSize;
}

- (CGSize)contentSizeForViewInPopover
{
	return self.topViewController.contentSizeForViewInPopover;
}

- (void)setNavigationBarHidden:(BOOL)navigationBarHidden animated:(BOOL)animated
{
    if (_navigationBarHidden != navigationBarHidden) {
        _navigationBarHidden = navigationBarHidden;
        [UIView animateWithDuration:animated ? kAnimationDuration : 0 
            animations:^{
                CGRect oldNavBarFrame = _navigationBar.frame;
                CGRect oldUserViewFrame = _containerView.frame;
                CGFloat yDelta = navigationBarHidden ? -oldNavBarFrame.size.height : oldNavBarFrame.size.height;

                CGRect newNavBarFrame = CGRectOffset(oldNavBarFrame, 0, yDelta);
                CGRect newUserViewFrame = {
                    .origin = {
                        .x = oldUserViewFrame.origin.x,
                        .y = MAX(0, oldUserViewFrame.origin.y + yDelta),
                    },
                    .size = {
                        .width = oldUserViewFrame.size.width,
                        .height = MIN(self.view.bounds.size.height, oldUserViewFrame.size.height - yDelta)
                    }
                };
                
                _navigationBar.frame = newNavBarFrame;
                _containerView.frame = newUserViewFrame;
            }
        ];
    }
}

- (void)setNavigationBarHidden:(BOOL)navigationBarHidden
{
    [self setNavigationBarHidden:navigationBarHidden animated:NO];
}

@end
