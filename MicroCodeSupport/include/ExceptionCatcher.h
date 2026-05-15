#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ExceptionCatcher : NSObject

/**
 * Executes a block of code and catches any Objective-C NSException that occurs.
 * returns YES if success, NO if exception occurred.
 * The error parameter is populated with a robust NSError describing the exception.
 */
+ (BOOL)catchException:(void(^)(void))tryBlock error:(__autoreleasing NSError **)error;

@end

NS_ASSUME_NONNULL_END
