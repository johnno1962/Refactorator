//
//  SwifactorPlugin.h
//  Swifactor
//
//  Created by John Holdsworth on 01/05/2014.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Swifactor/Classes/SwifactorPlugin.h#1 $
//
//  Repo: https://github.com/johnno1962/Swifactor
//

@import Foundation;

#define SWIFACTOR_SERVICE "service.swifactor"

@protocol SwifactorResponse

- (oneway void)error:(NSString * _Nonnull)msg;
- (oneway void)foundUSR:(NSString * _Nonnull)usr;
- (oneway void)willPatchFile:(NSString * _Nonnull)file line:(int)line col:(int)col text:(NSString * _Nonnull)text;
- (oneway void)log:(NSString * _Nonnull)msg;

@end

@protocol SwifactorRequest

- (int)refactorFile:(NSString * _Nonnull)filePath byteOffset:(int)offset oldValue:(NSString * _Nonnull)old
             logDir:(NSString * _Nonnull)logDir plugin:(id<SwifactorResponse> _Nonnull)plugin;
- (int)refactorFrom:(NSString * _Nonnull)oldValue to:(NSString * _Nonnull)newValue;
- (int)confirmRefactor;

@end

@interface SwifactorPlugin : NSObject <SwifactorResponse>

@end
