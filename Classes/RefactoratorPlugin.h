//
//  RefactoratorPlugin.h
//  Refactorator
//
//  Created by John Holdsworth on 01/05/2014.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/Classes/RefactoratorPlugin.h#3 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//

#import <Cocoa/Cocoa.h>

#define REFACTORATOR_SERVICE "service.refactorator"

@protocol RefactoratorResponse

- (oneway void)error:(NSString * _Nonnull)msg;
- (oneway void)foundUSR:(NSString * _Nonnull)usr;
- (oneway void)willPatchFile:(NSString * _Nonnull)file line:(int)line col:(int)col text:(NSString * _Nonnull)text;

@end

@protocol RefactoratorRequest

- (int)refactorFile:(NSString * _Nonnull)filePath byteOffset:(int)offset old:(NSString * _Nonnull)old
             logDir:(NSString * _Nonnull)logDir plugin:(id<RefactoratorResponse> _Nonnull)plugin;
- (int)refactorFrom:(NSString * _Nonnull)oldValue to:(NSString * _Nonnull)newValue;
- (int)confirmRefactor;

@end

@interface RefactoratorPlugin : NSObject <RefactoratorResponse>

@end
