// MicroKernel.mm
#import "MicroKernel.h"
#include <iostream>
#include <sys/sysctl.h>
#include <sys/utsname.h>

// --- C++ Implementation (Apple Silicon ARM64 PAC & ARC Safe) ---

void MicroGuard::logSystemInfo() {
    struct utsname systemInfo;
    uname(&systemInfo);

    int cpuCount = 0;
    int pCores = 0;
    int eCores = 0;
    uint64_t memSize = 0;
    size_t len = sizeof(cpuCount);
    sysctlbyname("hw.ncpu", &cpuCount, &len, NULL, 0);
    len = sizeof(pCores);
    sysctlbyname("hw.perflevel0.physicalcpu", &pCores, &len, NULL, 0);
    len = sizeof(eCores);
    sysctlbyname("hw.perflevel1.physicalcpu", &eCores, &len, NULL, 0);
    len = sizeof(memSize);
    sysctlbyname("hw.memsize", &memSize, &len, NULL, 0);

    std::cout << "=== Apple Silicon UMA Kernel Info ===" << std::endl;
    std::cout << "Kernel Name: " << systemInfo.sysname << " " << systemInfo.release << std::endl;
    std::cout << "Machine:     " << systemInfo.machine << std::endl;
    std::cout << "CPU Cores:   " << cpuCount << " (" << pCores << " P-Cores + " << eCores << " E-Cores)" << std::endl;
    std::cout << "UMA Memory:  " << (memSize / (1024ULL * 1024ULL * 1024ULL)) << " GB Unified Pool" << std::endl;
    std::cout << "=====================================" << std::endl;
}

bool MicroGuard::executeSafe(std::function<void()> task) {
    if (!task) return false;

    // ARM64 PAC & ARC-safe Objective-C++ / C++ exception isolation.
    // Never use setjmp/longjmp across signal frames on Apple Silicon, as it
    // corrupts ARC reference counts and overwrites CrashReporter's signal handlers.
    @try {
        try {
            task();
            return true;
        } catch (const std::exception& e) {
            std::cerr << "[MicroVM] Caught C++ Exception: " << e.what() << std::endl;
            return false;
        } catch (...) {
            std::cerr << "[MicroVM] Caught Unknown C++ Exception" << std::endl;
            return false;
        }
    } @catch (NSException *exception) {
        std::cerr << "[MicroVM] Caught Obj-C Exception: " << [exception.name UTF8String]
                  << " (" << (exception.reason ? [exception.reason UTF8String] : "no reason") << ")" << std::endl;
        return false;
    }
}

@implementation SystemUtils
+ (NSString *)getOSVersionDetail {
    NSProcessInfo *pInfo = [NSProcessInfo processInfo];
    return [NSString stringWithFormat:@"%@ Version %@", [pInfo operatingSystemVersionString], pInfo.hostName];
}
@end

@implementation MicroVM

+ (BOOL)executeSafe:(void(NS_NOESCAPE ^)(void))block {
    if (!block) return NO;

    // Convert Obj-C Block to C++ Lambda
    // Note: We use a simple lambda that calls the block.
    // The block is invoked synchronously, so stack-based capture is fine.
    return MicroGuard::executeSafe([block]() {
        block();
    });
}

@end
