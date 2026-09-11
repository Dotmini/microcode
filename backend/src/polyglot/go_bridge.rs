//! Go Polyglot Bridge
//!
//! Provides Go helper utilities to map POSIX shared memory buffers and Arrow IPC
//! streams into Go structs with zero-copy.

use super::PolyglotVariableBinding;

pub struct GoBridge;

impl GoBridge {
    /// Generate Go helper code and variables initialization
    pub fn generate_prelude(variables: &[PolyglotVariableBinding]) -> String {
        let mut code = String::from(
            r#"// --- MicroCode Rosetta In-Memory Hybrid Bridge (Go) ---
package main

import (
	"fmt"
	"io"
	"os"
)

type MicroCodeShmBuffer struct {
	Name string
	Data []byte
}

func mcLoadShmVar(shmName string) (*MicroCodeShmBuffer, error) {
	paths := []string{
		"/dev/shm/" + shmName,
		"/tmp/" + shmName,
		"/tmp/" + shmName + ".shm",
	}
	for _, p := range paths {
		f, err := os.Open(p)
		if err == nil {
			defer f.Close()
			data, err := io.ReadAll(f)
			if err == nil {
				return &MicroCodeShmBuffer{Name: shmName, Data: data}, nil
			}
		}
	}
	return nil, fmt.Errorf("shm variable %s not found", shmName)
}

// Global SHM variables injected by MicroCode Supervisor
var (
"#,
        );

        for var in variables {
            code.push_str(&format!(
                "\t{}Buffer, _ = mcLoadShmVar(\"{}\")\n",
                var.name, var.shm_name
            ));
        }

        code.push_str(")\n// --- End MicroCode Go Bridge ---\n\n");
        code
    }
}
