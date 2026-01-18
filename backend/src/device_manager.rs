use std::ffi::CStr;
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn mc_on_device_connected(vid: u16, pid: u16, port: *const c_char) {
    let port_str = unsafe {
        if port.is_null() {
            return;
        }
        CStr::from_ptr(port).to_string_lossy().into_owned()
    };

    // Filter for Espressif or common USB-to-UART bridges
    // Espressif: 303A
    // Silicon Labs (CP210x): 10C4
    // WCH (CH340): 1A86
    let is_espressif_related = match vid {
        0x303A => true,
        0x10C4 => true,
        0x1A86 => true,
        _ => false,
    };

    if is_espressif_related {
        println!("[DeviceManager] Detected ESP32-related device: VID={:04X} PID={:04X} Port={}", vid, pid, port_str);
        // In a real app, we would broadcast this event to the frontend via IPC/Callback
    } else {
        println!("[DeviceManager] Ignored device: VID={:04X} PID={:04X}", vid, pid);
    }
}
