#import "FrameworkLoader.h"
#include <dlfcn.h>
#include <iostream>

// Objective-C++ Implementation
@implementation FrameworkLoader

+ (BOOL)loadFrameworkAtPath:(NSString *)path error:(__autoreleasing NSError **)error {
    if (!path || path.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.codetunner.kernel" code:1001 userInfo:@{NSLocalizedDescriptionKey: @"Invalid path"}];
        }
        return NO;
    }

    // Try standard NSBundle load first (ObjC way)
    NSBundle *bundle = [NSBundle bundleWithPath:path];
    if (bundle) {
        NSError *loadError = nil;
        if ([bundle loadAndReturnError:&loadError]) {
            std::cout << "[Kernel] Successfully loaded framework via NSBundle: " << [path UTF8String] << std::endl;
            return YES;
        } else {
            // Fallback to dlopen (C++ way)
            std::cerr << "[Kernel] NSBundle failed. Attempting dlopen fallback..." << std::endl;
        }
    }

    // Direct dlopen for libs/frameworks not conforming strictly to Bundle structure
    void *handle = dlopen([path UTF8String], RTLD_NOW | RTLD_GLOBAL);
    if (handle) {
        std::cout << "[Kernel] Successfully loaded binary via dlopen: " << [path UTF8String] << std::endl;
        return YES;
    } else {
        const char *err = dlerror();
        NSString *reason = err ? [NSString stringWithUTF8String:err] : @"Unknown dlopen error";
        if (error) {
            *error = [NSError errorWithDomain:@"com.codetunner.kernel" code:1002 userInfo:@{NSLocalizedDescriptionKey: reason}];
        }
        return NO;
    }
}

+ (BOOL)isClassAvailable:(NSString *)className {
    if (!className) return NO;
    return NSClassFromString(className) != nil;
}

@end
