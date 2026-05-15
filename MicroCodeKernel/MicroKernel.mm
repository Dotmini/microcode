// MicroKernel.mm
#import "MicroKernel.h"
#include <iostream>
#include <sys/sysctl.h> // เข้าถึง Kernel state
#include <sys/utsname.h>
#include <csetjmp>      // สำหรับกระโดดข้าม Crash (Non-local goto)
#include <csignal>      // สำหรับดักจับ Signal ระดับต่ำ (SIGSEGV, SIGBUS)

// --- Global Buffer สำหรับกู้คืนสถานะ CPU ---
static std::jmp_buf jump_buffer;

// --- Signal Handler ---
// ทำหน้าที่รับแรงกระแทกเมื่อเกิด Crash ระดับ Hardware (เช่น เข้าถึง Pointer เถื่อน)
void signal_handler(int signal) {
    std::cerr << "\n[MicroVM Panic] Caught Low-Level Signal: " << signal << std::endl;
    std::cerr << "[MicroVM Recovery] Restoring CPU context..." << std::endl;

    // กระโดดกลับไปยังจุดที่ปลอดภัย (longjmp)
    std::longjmp(jump_buffer, 1);
}

// --- C++ Implementation ---

void MicroGuard::logSystemInfo() {
    // 1. ใช้ uname เพื่อดึงข้อมูล Kernel ระดับต่ำ
    struct utsname systemInfo;
    uname(&systemInfo);

    std::cout << "=== Low-Level OS Info ===" << std::endl;
    std::cout << "Kernel Name: " << systemInfo.sysname << std::endl;
    std::cout << "Node Name:   " << systemInfo.nodename << std::endl;
    std::cout << "Release:     " << systemInfo.release << std::endl;
    std::cout << "Version:     " << systemInfo.version << std::endl;
    std::cout << "Machine:     " << systemInfo.machine << std::endl; // เช่น arm64

    // 2. ใช้ sysctl ดึงจำนวน CPU
    int mib[2];
    size_t len;
    mib[0] = CTL_HW;
    mib[1] = HW_NCPU;
    int cpuCount;
    len = sizeof(cpuCount);
    sysctl(mib, 2, &cpuCount, &len, NULL, 0);
    std::cout << "Physical CPU Cores: " << cpuCount << std::endl;
    std::cout << "=========================" << std::endl;
}

bool MicroGuard::executeSafe(std::function<void()> task) {
    std::cout << "[MicroVM] Starting isolated execution..." << std::endl;

    // 1. ลงทะเบียน Signal Handler (ดักจับ Crash ระดับต่ำสุด)
    // SIGSEGV = Segmentation Fault (เข้าถึงแรมผิด)
    // SIGBUS = Bus Error
    // SIGFPE = Floating Point Exception (หารศูนย์)
    std::signal(SIGSEGV, signal_handler);
    std::signal(SIGBUS,  signal_handler);
    std::signal(SIGFPE,  signal_handler);

    // 2. Set Jump Point (จุด Save Point)
    // ถ้า setjmp คืนค่า 0 คือการรันปกติ
    // ถ้าคืนค่าอื่น แสดงว่าถูกโยนมาจาก signal_handler (เกิด Crash)
    if (setjmp(jump_buffer) == 0) {

        // 3. ป้องกันระดับ Objective-C และ C++ Exception
        @try {
            try {
                // *** รันโค้ดของผู้ใช้ที่นี่ ***
                task();

            } catch (const std::exception& e) {
                std::cerr << "[MicroVM] Caught C++ Exception: " << e.what() << std::endl;
                return false;
            } catch (...) {
                std::cerr << "[MicroVM] Caught Unknown C++ Exception" << std::endl;
                return false;
            }
        } @catch (NSException *exception) {
            std::cerr << "[MicroVM] Caught Obj-C Exception: " << [exception.name UTF8String] << std::endl;
            return false;
        } @finally {
            // Cleanup code if needed
        }

    } else {
        // เข้าที่นี่เมื่อเกิด Fatal Crash แล้วถูกกู้คืนโดย longjmp
        std::cerr << "[MicroVM] FATAL CRASH DETECTED! Execution terminated safely. App is still alive." << std::endl;

        // Reset signal handler เพื่อป้องกัน Loop นรก
        std::signal(SIGSEGV, SIG_DFL);
        return false;
    }

    std::cout << "[MicroVM] Execution completed successfully." << std::endl;
    return true;
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
