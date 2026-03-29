#ifndef VM_BRIDGE_H
#define VM_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque pointer to the VM configuration wrapper
typedef void* VMConfigRef;

// Callback for console output
typedef void (*ConsoleCallback)(const char* data);

// Create a new VM configuration
// linux_iso_path: Path to the Alpine Linux ISO (or kernel/initrd if we go that route, but sticking to detailed impl)
// For this focused implementation, we'll assume we are booting a Linux kernel directly.
// kernel_path: Path to vmlinuz
// initrd_path: Path to initramfs
VMConfigRef create_vm_config(const char* kernel_path, const char* initrd_path, const char* cmdline);

// Configure a shared directory using VirtioFS
// config: The VM configuration object
// host_path: The directory on macOS to share
// mount_tag: The tag to use for mounting (e.g., "microcode_share")
void configure_shared_directory(VMConfigRef config, const char* host_path, const char* mount_tag);

// Set the console output callback
void register_console_callback(ConsoleCallback callback);

// Start the VM
// Returns true on success, false on failure
bool start_vm(VMConfigRef config);

// Stop the VM
void stop_vm();

#ifdef __cplusplus
}
#endif

#endif // VM_BRIDGE_H
