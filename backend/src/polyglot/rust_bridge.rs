//! Rust Polyglot Bridge
//!
//! Provides Rust cells with direct Zero-Copy access to Polars DataFrames
//! and Arrow RecordBatches residing in MicroCode Shared Memory.

use super::PolyglotVariableBinding;

pub struct RustBridge;

impl RustBridge {
    /// Generate Rust helper preamble to load SHM variables into Polars DataFrames
    pub fn generate_prelude(variables: &[PolyglotVariableBinding]) -> String {
        let mut code = String::from(
            r#"// --- MicroCode Rosetta In-Memory Hybrid Bridge (Rust) ---
use std::fs::File;
use std::path::Path;

#[allow(dead_code)]
fn mc_load_shm_dataframe(shm_name: &str) -> Option<polars::prelude::DataFrame> {
    use polars::prelude::*;
    let candidates = [
        format!("/dev/shm/{}", shm_name),
        format!("/tmp/{}", shm_name),
        format!("/tmp/{}.shm", shm_name),
    ];
    for p in &candidates {
        if Path::new(p).exists() {
            if let Ok(file) = File::open(p) {
                if let Ok(df) = IpcReader::new(file).finish() {
                    return Some(df);
                }
            }
        }
    }
    None
}
"#,
        );

        code.push_str("// Auto-injected MicroCode SHM Variables\n");
        for var in variables {
            code.push_str(&format!(
                "let {} = mc_load_shm_dataframe(\"{}\");\n",
                var.name, var.shm_name
            ));
        }

        code.push_str("// --- End MicroCode Rust Bridge ---\n\n");
        code
    }
}
