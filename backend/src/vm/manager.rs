use std::ffi::{c_void, CString};
use std::sync::{Arc, Mutex};

// FFI Definitions
#[repr(C)]
struct VMConfigRef(*mut c_void);

#[link(name = "vm_bridge", kind = "static")]
extern "C" {
    fn create_vm_config(
        kernel_path: *const i8,
        initrd_path: *const i8,
        cmdline: *const i8,
    ) -> *mut c_void;
    fn configure_shared_directory(config: *mut c_void, host_path: *const i8, mount_tag: *const i8);
    fn register_console_callback(callback: extern "C" fn(*const i8));
    fn start_vm(config: *mut c_void) -> bool;
    fn stop_vm();
}

// Rust callback wrapper
extern "C" fn console_callback_wrapper(data: *const i8) {
    if data.is_null() {
        return;
    }
    unsafe {
        if let Ok(str_slice) = std::ffi::CStr::from_ptr(data).to_str() {
            // In a real app, send this to a WebSocket or channel
            print!("{}", str_slice);
        }
    }
}

pub struct MicroVM {
    config: *mut c_void,
}

unsafe impl Send for MicroVM {}
unsafe impl Sync for MicroVM {}

impl MicroVM {
    pub fn new(kernel: &str, initrd: &str, cmdline: Option<&str>) -> Self {
        let k = CString::new(kernel).unwrap();
        let i = CString::new(initrd).unwrap();
        let c = cmdline.map(|s| CString::new(s).unwrap());

        let config_ptr = unsafe {
            create_vm_config(
                k.as_ptr(),
                i.as_ptr(),
                c.map(|s| s.as_ptr()).unwrap_or(std::ptr::null()),
            )
        };

        // Register console globally for now
        unsafe { register_console_callback(console_callback_wrapper) };

        Self { config: config_ptr }
    }

    pub fn mount_project_folder(&self, host_path: &str) {
        if self.config.is_null() {
            return;
        }

        let path = CString::new(host_path).unwrap();
        let tag = CString::new("microcode_share").unwrap();

        unsafe {
            configure_shared_directory(self.config, path.as_ptr(), tag.as_ptr());
        }
    }

    pub fn start(&self) -> Result<(), String> {
        if self.config.is_null() {
            return Err("Invalid config".to_string());
        }

        let success = unsafe { start_vm(self.config) };
        if success {
            Ok(())
        } else {
            Err("Failed to start VM".to_string())
        }
    }

    pub fn stop() {
        unsafe { stop_vm() };
    }
}
