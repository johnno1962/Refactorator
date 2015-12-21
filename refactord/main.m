//
//  main.m
//  refactord
//
//  Created by John Holdsworth on 19/12/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/refactord/main.m#3 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//

#import <Foundation/Foundation.h>
#import "../Classes/RefactoratorPlugin.h"
#import "refactord-Swift.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        Refactorator *service = [Refactorator new];
        NSConnection *xcodeConnection = [NSConnection serviceConnectionWithName:@REFACTORATOR_SERVICE rootObject:service];
        [[NSRunLoop mainRunLoop] run];
        xcodeConnection = nil;
    }
    return 0;
}
