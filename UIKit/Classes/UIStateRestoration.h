//
//  UIStateRestoration.h
//  UIKit
//
//  Created by eggers on 18/04/13.
//
//

#import <Foundation/Foundation.h>

@protocol UIViewControllerRestoration
+ (UIViewController *) viewControllerWithRestorationIdentifierPath:(NSArray *)identifierComponents coder:(NSCoder *)coder;
@end