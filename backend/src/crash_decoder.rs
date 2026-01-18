use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};
use regex::Regex;

#[repr(C)]
pub struct CrashReport {
    pub exception_type: *mut c_char,
    pub pc_address: *mut c_char,
}

#[no_mangle]
pub extern "C" fn mc_decode_serial_line(line: *const c_char) -> *mut CrashReport {
    let line_str = unsafe {
        if line.is_null() {
            return std::ptr::null_mut();
        }
        CStr::from_ptr(line).to_string_lossy()
    };

    if !line_str.contains("Guru Meditation Error") {
        return std::ptr::null_mut();
    }

    // Example: "Guru Meditation Error: Core  1 panic'ed (LoadProhibited). Exception was unhandled."
    // Captures the part after "Error: " until the dot.
    let re = Regex::new(r"Guru Meditation Error:\s*(.*?)(\.|$)").unwrap();
    
    if let Some(caps) = re.captures(&line_str) {
        let exception_msg = caps.get(1).map_or("", |m| m.as_str());
        
        // Placeholder PC Address as it's often in subsequent lines
        let pc_address = "0x00000000"; 

        let c_exception = CString::new(exception_msg).unwrap();
        let c_pc = CString::new(pc_address).unwrap();

        let report = Box::new(CrashReport {
            exception_type: c_exception.into_raw(),
            pc_address: c_pc.into_raw(),
        });

        return Box::into_raw(report);
    }

    std::ptr::null_mut()
}

#[no_mangle]
pub extern "C" fn mc_free_crash_report(report: *mut CrashReport) {
    if report.is_null() { return; }
    unsafe {
        let report = Box::from_raw(report);
        // Re-take ownership of CStrings to free them
        if !report.exception_type.is_null() {
            let _ = CString::from_raw(report.exception_type);
        }
        if !report.pc_address.is_null() {
            let _ = CString::from_raw(report.pc_address);
        }
        // report dropped here
    }
}
