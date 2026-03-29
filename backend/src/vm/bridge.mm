#import <Foundation/Foundation.h>
#import <Virtualization/Virtualization.h>
#include "bridge.h"

// Global VM state (simplified for this specific task)
static VZVirtualMachine *globalVM = nil;
static ConsoleCallback globalConsoleCallback = nil;

// Helper class to capture serial output
// Helper class to capture serial output - REMOVED (Using Pipe directly)
// @interface SerialPortDelegate : NSObject <VZSerialPortAttachment>
// @end

// Delegate implementation removed.

// Bridge Implementation

VMConfigRef create_vm_config(const char* kernel_path, const char* initrd_path, const char* cmdline) {
    if (!kernel_path || !initrd_path) return NULL;
    
    NSString *kernelPathStr = [NSString stringWithUTF8String:kernel_path];
    NSString *initrdPathStr = [NSString stringWithUTF8String:initrd_path];
    NSString *cmdLineStr = cmdline ? [NSString stringWithUTF8String:cmdline] : @"console=hvc0";
    
    NSURL *kernelURL = [NSURL fileURLWithPath:kernelPathStr];
    NSURL *initrdURL = [NSURL fileURLWithPath:initrdPathStr];
    
    VZLinuxBootLoader *bootLoader = [[VZLinuxBootLoader alloc] initWithKernelURL:kernelURL];
    bootLoader.initialRamdiskURL = initrdURL;
    bootLoader.commandLine = cmdLineStr;
    
    VZVirtualMachineConfiguration *config = [[VZVirtualMachineConfiguration alloc] init];
    config.bootLoader = bootLoader;
    
    // CPU & Memory
    config.CPUCount = 2; // Default to 2 cores
    config.memorySize = 2 * 1024 * 1024 * 1024ull; // 2 GB
    
    // Serial Console (for stdout interception)
    VZVirtioConsoleDeviceSerialPortConfiguration *consoleConfig = [[VZVirtioConsoleDeviceSerialPortConfiguration alloc] init];
    
    // We use a pipe to capture output.
    // In a real robust implementation, we'd use a more complex attachment.
    // For "Micro-VM Runner", capturing via a pipe attachment is standard.
    NSPipe *outputPipe = [NSPipe pipe];
    consoleConfig.attachment = [[VZFileHandleSerialPortAttachment alloc] initWithFileHandleForReading:nil fileHandleForWriting:outputPipe.fileHandleForWriting];
    
    config.serialPorts = @[consoleConfig];
    
    // Network (Optional, but good for Alpine to install packages)
    VZNATNetworkDeviceAttachment *natAttachment = [[VZNATNetworkDeviceAttachment alloc] init];
    VZVirtioNetworkDeviceConfiguration *networkConfig = [[VZVirtioNetworkDeviceConfiguration alloc] init];
    networkConfig.attachment = natAttachment;
    networkConfig.MACAddress = [VZMACAddress randomLocallyAdministeredAddress];
    config.networkDevices = @[networkConfig];
    
    // Entropy
    config.entropyDevices = @[[[VZVirtioEntropyDeviceConfiguration alloc] init]];
    
    // Keep pipe alive
    // In a full implementation, we'd manage lifetime better.
    // For now, we attach a read handler to the pipe.
    outputPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
         NSData *data = [handle availableData];
         if (data.length > 0 && globalConsoleCallback) {
             NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
             if (str) {
                 globalConsoleCallback([str UTF8String]);
             }
         }
    };
    
    return (__bridge_retained void*)config;
}

void configure_shared_directory(VMConfigRef config_ptr, const char* host_path, const char* mount_tag) {
    if (!config_ptr || !host_path || !mount_tag) return;
    
    VZVirtualMachineConfiguration *config = (__bridge VZVirtualMachineConfiguration *)config_ptr;
    
    NSString *hostPathStr = [NSString stringWithUTF8String:host_path];
    NSString *mountTagStr = [NSString stringWithUTF8String:mount_tag];
    
    NSURL *directoryURL = [NSURL fileURLWithPath:hostPathStr];
    
    // Create the shared directory object
    // VZSharedDirectory *sharedDirectory = [[VZSharedDirectory alloc] initWithURL:directoryURL readOnly:NO];
    // NOTE: VZSharedDirectory is for macOS 12+.
    
    // VZSharedDirectory *sharedDir = [[VZSharedDirectory alloc] initWithURL:directoryURL readOnly:NO]; 
    // VZSingleDirectoryShare *share = [[VZSingleDirectoryShare alloc] initWithDirectory:sharedDir];
    
    // NOTE: VZSharedDirectory API might differ or require specific construction.
    // For this bridge, assuming standard API availability.
    // If strict error handling is needed:
    // NSError *error = nil;
    VZSharedDirectory *sharedDir = [[VZSharedDirectory alloc] initWithURL:directoryURL readOnly:NO];
    VZSingleDirectoryShare *share = [[VZSingleDirectoryShare alloc] initWithDirectory:sharedDir];
    
    VZVirtioFileSystemDeviceConfiguration *fsConfig = [[VZVirtioFileSystemDeviceConfiguration alloc] initWithTag:mountTagStr];
    fsConfig.share = share;
    
    // Add to config (mutable array check)
    NSMutableArray *storageDevices = [config.directorySharingDevices mutableCopy];
    [storageDevices addObject:fsConfig];
    config.directorySharingDevices = storageDevices;
    
    NSLog(@"[MicroVM] Configured VirtioFS: Host='%@' -> Tag='%@'", hostPathStr, mountTagStr);
}

void register_console_callback(ConsoleCallback callback) {
    globalConsoleCallback = callback;
}

bool start_vm(VMConfigRef config_ptr) {
    if (!config_ptr) return false;
    
    VZVirtualMachineConfiguration *config = (__bridge VZVirtualMachineConfiguration *)config_ptr;
    
    NSError *error = nil;
    if (![config validateWithError:&error]) {
        NSLog(@"[MicroVM] Validation failed: %@", error);
        return false;
    }
    
    globalVM = [[VZVirtualMachine alloc] initWithConfiguration:config];
    
    [globalVM startWithCompletionHandler:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"[MicroVM] Failed to start: %@", error);
            if (globalConsoleCallback) {
                NSString *errStr = [NSString stringWithFormat:@"[Error] VM Start Failed: %@", error.localizedDescription];
                globalConsoleCallback([errStr UTF8String]);
            }
        } else {
            NSLog(@"[MicroVM] Started successfully.");
            if (globalConsoleCallback) {
                globalConsoleCallback("[System] MicroVM Started.\n");
            }
        }
    }];
    
    return true;
}

void stop_vm() {
    if (globalVM) {
        [globalVM stopWithCompletionHandler:^(NSError * _Nullable error) {
            if (error) {
                 NSLog(@"[MicroVM] Stop error: %@", error);
            } else {
                 NSLog(@"[MicroVM] Stopped.");
            }
        }];
        globalVM = nil;
    }
}
