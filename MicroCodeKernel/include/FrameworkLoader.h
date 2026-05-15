#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Kernel-level Framework Loader handling dynamic linking.
 * Implemented in Objective-C++ to allow future integration with C++ based loading mechanisms.
 */
@interface FrameworkLoader : NSObject

/**
 * Attempts to load a private or system framework dynamically.
 * @param path Absolute path to the .framework bundle.
 * @return YES if loaded successfully, NO otherwise.
 */
+ (BOOL)loadFrameworkAtPath:(NSString *)path error:(__autoreleasing NSError **)error;

/**
 * Checks if a specific class is available in the runtime (useful after loading).
 */
+ (BOOL)isClassAvailable:(NSString *)className;

@end

NS_ASSUME_NONNULL_END
