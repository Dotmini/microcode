//! Objective-C Polyglot Bridge
//!
//! Maps MicroCode Arrow Shared Memory segments directly into Apple Foundation
//! NSData with zero-copy (`dataWithBytesNoCopy:length:freeWhenDone:NO`).

use super::PolyglotVariableBinding;

pub struct ObjCBridge;

impl ObjCBridge {
    /// Generate Objective-C prelude code
    pub fn generate_prelude(variables: &[PolyglotVariableBinding]) -> String {
        let mut code = String::from(
            r#"// --- MicroCode Rosetta In-Memory Hybrid Bridge (Objective-C) ---
#import <Foundation/Foundation.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

static inline NSData* _Nullable mc_load_shm_nsdata(NSString* _Nonnull shmName) {
    const char* cname = [shmName UTF8String];
    int fd = shm_open(cname, O_RDONLY, 0);
    if (fd < 0) {
        NSString* fallback = [NSString stringWithFormat:@"/tmp/%@", shmName];
        fd = open([fallback UTF8String], O_RDONLY);
    }
    if (fd < 0) return nil;
    
    struct stat sb;
    if (fstat(fd, &sb) != 0 || sb.st_size <= 0) {
        close(fd);
        return nil;
    }
    
    void* addr = mmap(NULL, sb.st_size, PROT_READ, MAP_SHARED, fd, 0);
    close(fd);
    if (addr == MAP_FAILED) return nil;
    
    // Zero-copy wrap into NSData
    return [NSData dataWithBytesNoCopy:addr length:(NSUInteger)sb.st_size freeWhenDone:NO];
}
"#,
        );

        for var in variables {
            code.push_str(&format!(
                "NSData* {} = mc_load_shm_nsdata(@\"{}\");\n",
                var.name, var.shm_name
            ));
        }

        code.push_str("// --- End MicroCode Objective-C Bridge ---\n\n");
        code
    }
}
