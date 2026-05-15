#import "ExceptionCatcher.h"

@implementation ExceptionCatcher

+ (BOOL)catchException:(void(^)(void))tryBlock error:(__autoreleasing NSError **)error {
    @try {
        tryBlock();
        return YES;
    }
    @catch (NSException *exception) {
        if (error) {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
            if (exception.name) userInfo[@"ExceptionName"] = exception.name;
            if (exception.reason) userInfo[NSLocalizedFailureReasonErrorKey] = exception.reason;
            if (exception.callStackSymbols) userInfo[@"CallStack"] = exception.callStackSymbols;
            
            *error = [NSError errorWithDomain:@"com.codetunner.exception"
                                         code:999
                                     userInfo:userInfo];
        }
        return NO;
    }
}

@end
