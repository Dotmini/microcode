// MicroKernel.h
#import <Foundation/Foundation.h>

#ifdef __cplusplus
#include <functional> // สำหรับ C++ std::function

// ใช้ C++ Class ผสมกับ Objective-C
class MicroGuard {
public:
    // ฟังก์ชันตรวจสอบ OS ระดับ Kernel (sysctl)
    static void logSystemInfo();

    // ตัวรันโค้ดแบบ MicroVM (Sandboxed Execution)
    // รับ Lambda function ของ C++ เข้ามาทำงาน
    static bool executeSafe(std::function<void()> task);
};
#endif

@interface SystemUtils : NSObject
+ (NSString *)getOSVersionDetail;
@end

/**
 * Objective-C Wrapper for MicroKVMMachine (MicroGuard).
 * Allows Swift to execute code within the signal-guarded sandbox.
 */
@interface MicroVM : NSObject

/**
 * Executes a block safely within the MicroVM sandbox.
 * Catches C++ exceptions, Obj-C exceptions, and Low-Level Signals (SEGFAULT/BUS).
 */
+ (BOOL)executeSafe:(void(NS_NOESCAPE ^)(void))block;

@end