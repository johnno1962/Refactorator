//
//  main.m
//  refactord
//
//  Created by John Holdsworth on 19/12/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Swifactor/refactord/main.m#1 $
//
//  Repo: https://github.com/johnno1962/Swifactor
//

#import "../Classes/SwifactorPlugin.h"
#import "refactord-Swift.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        Swifactor *service = [Swifactor new];
        NSConnection *xcodeConnection = [NSConnection serviceConnectionWithName:@SWIFACTOR_SERVICE rootObject:service];
        [[NSRunLoop mainRunLoop] run];
        xcodeConnection = nil;
    }
    return 0;
}
