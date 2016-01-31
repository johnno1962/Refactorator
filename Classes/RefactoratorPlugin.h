//
//  RefactoratorPlugin.h
//  Refactorator
//
//  Created by John Holdsworth on 01/05/2014.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/Classes/RefactoratorPlugin.h#20 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//

@import Foundation;

#define REFACTORATOR_SERVICE @"service.refactorator"

@protocol RefactoratorResponse

- (oneway void)error:(NSString *__nonnull)msg;
- (oneway void)indexing:(NSString * __nullable)file;
- (oneway void)foundUSR:(NSString * __nonnull)usr text:(NSString * __nonnull)text;
- (oneway void)willPatchFile:(NSString * __nonnull)file line:(int)line col:(int)col text:(NSString * __nonnull)text;
- (oneway void)log:(NSString * __nonnull)msg;

@end

@protocol RefactoratorRequest

- (int)refactorFile:(NSString * __nonnull)filePath byteOffset:(int)offset oldValue:(NSString * __nonnull)old
             logDir:(NSString * __nonnull)logDir graph:(NSString * __nullable)graph
            indexDB:(NSString * __nonnull)indexDB plugin:(id<RefactoratorResponse> __nonnull)plugin;
- (int)refactorFrom:(NSString * __nonnull)oldValue to:(NSString * __nonnull)newValue;
- (int)confirmRefactor;
- (int)revertRefactor;

@end

@interface RefactoratorPlugin : NSObject <RefactoratorResponse>

@end
