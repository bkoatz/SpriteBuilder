//
//  LocalizationTranslateWindowHandler.m
//  SpriteBuilder
//
//  Created by Benjamin Koatz on 6/23/14.
//
//

#import "LocalizationTranslateWindowHandler.h"
#import "LocalizationTranslateWindow.h"

@implementation LocalizationTranslateWindowHandler

/*
 * Allows translate window to cancel the current URL task (unless its going to be a background
 * translation download) and close itself from a modal state
 */
-(void)close{
    LocalizationTranslateWindow *wc = [self windowController];
    NSURLSessionTask *ct = [wc currTask];
    if(ct && ct.state !=
       NSURLSessionTaskStateCompleted && ![ct.taskDescription isEqualToString:@"translations"])
    {
        [ct cancel];
    }
    if([self isModalPanel]){
        [NSApp endSheet:self];
        [self orderOut:nil];
    }
}
@end
