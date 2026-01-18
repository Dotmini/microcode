#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char* exception_type;
    char* pc_address;
} CrashReport;

// Rust FFI Functions
void mc_on_device_connected(unsigned short vid, unsigned short pid, const char* port);
CrashReport* mc_decode_serial_line(const char* line);
void mc_free_crash_report(CrashReport* report);

#ifdef __cplusplus
}
#endif
