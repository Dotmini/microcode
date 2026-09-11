//! C and C++ Polyglot Bridge
//!
//! Provides C/C++ cells with standard Arrow C Data Interface structures
//! and POSIX memory-mapped buffer access.

use super::PolyglotVariableBinding;

pub struct CppBridge;

impl CppBridge {
    /// Generate C++ prelude code
    pub fn generate_prelude(variables: &[PolyglotVariableBinding]) -> String {
        let mut code = String::from(
            r#"// --- MicroCode Rosetta In-Memory Hybrid Bridge (C/C++) ---
#include <iostream>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <string>

// Arrow C Data Interface structures
#ifndef ARROW_C_DATA_INTERFACE
#define ARROW_C_DATA_INTERFACE

struct ArrowSchema {
    const char* format;
    const char* name;
    const char* metadata;
    int64_t flags;
    int64_t n_children;
    struct ArrowSchema** children;
    struct ArrowSchema* dictionary;
    void (*release)(struct ArrowSchema*);
    void* private_data;
};

struct ArrowArray {
    int64_t length;
    int64_t null_count;
    int64_t offset;
    int64_t n_buffers;
    int64_t n_children;
    const void** buffers;
    struct ArrowArray** children;
    struct ArrowArray* dictionary;
    void (*release)(struct ArrowArray*);
    void* private_data;
};
#endif

struct MicroCodeShmBuffer {
    const uint8_t* data;
    size_t size;
    int fd;
};

inline MicroCodeShmBuffer mc_load_shm_buffer(const std::string& shm_name) {
    MicroCodeShmBuffer buf = {nullptr, 0, -1};
    int fd = shm_open(shm_name.c_str(), O_RDONLY, 0);
    if (fd < 0) {
        std::string fallback = "/tmp/" + shm_name;
        fd = open(fallback.c_str(), O_RDONLY);
    }
    if (fd >= 0) {
        struct stat sb;
        if (fstat(fd, &sb) == 0 && sb.st_size > 0) {
            void* addr = mmap(NULL, sb.st_size, PROT_READ, MAP_SHARED, fd, 0);
            if (addr != MAP_FAILED) {
                buf.data = static_cast<const uint8_t*>(addr);
                buf.size = static_cast<size_t>(sb.st_size);
                buf.fd = fd;
            }
        }
    }
    return buf;
}
"#,
        );

        for var in variables {
            code.push_str(&format!(
                "auto {} = mc_load_shm_buffer(\"{}\");\n",
                var.name, var.shm_name
            ));
        }

        code.push_str("// --- End MicroCode C/C++ Bridge ---\n\n");
        code
    }
}
