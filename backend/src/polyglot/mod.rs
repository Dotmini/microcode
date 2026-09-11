//! MicroCode Polyglot In-Memory Bridge
//!
//! Provides zero-config prelude and postlude shims for 10 languages:
//! - Python
//! - R
//! - Julia
//! - SQL (DuckDB / Polars)
//! - Ardium v2.3
//! - Objective-C
//! - Rust
//! - Go
//! - C / C++
//! - R Markdown
//!
//! Copyright © 2026 Dotmini Software (Tirawat Nantamas). All rights reserved.

pub mod python_bridge;
pub mod sql_bridge;
pub mod ardium_bridge;
pub mod r_bridge;
pub mod julia_bridge;
pub mod go_bridge;
pub mod rust_bridge;
pub mod cpp_bridge;
pub mod objc_bridge;

use serde::{Deserialize, Serialize};
use self::python_bridge::PythonBridge;
use self::ardium_bridge::ArdiumBridge;
use self::r_bridge::RBridge;
use self::julia_bridge::JuliaBridge;
use self::go_bridge::GoBridge;
use self::rust_bridge::RustBridge;
use self::cpp_bridge::CppBridge;
use self::objc_bridge::ObjCBridge;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PolyglotVariableBinding {
    pub name: String,
    pub shm_name: String,
    pub data_type: String,
    pub num_rows: Option<u64>,
    pub num_cols: Option<u64>,
}

pub struct PolyglotBridge;

impl PolyglotBridge {
    /// Injects language-specific prelude shims into the user's cell code
    pub fn inject_prelude(language: &str, user_code: &str, variables: &[PolyglotVariableBinding]) -> String {
        if variables.is_empty() {
            return user_code.to_string();
        }

        let prelude = match language.to_lowercase().as_str() {
            "python" | "py" => PythonBridge::generate_prelude(variables),
            "r" => RBridge::generate_prelude(variables),
            "rmarkdown" | "r_markdown" | "rmd" => RBridge::generate_prelude(variables),
            "julia" | "jl" => JuliaBridge::generate_prelude(variables),
            "ardium" | "ar" => ArdiumBridge::generate_prelude(variables),
            "go" | "golang" => GoBridge::generate_prelude(variables),
            "rust" | "rs" => RustBridge::generate_prelude(variables),
            "c" | "cpp" | "c++" => CppBridge::generate_prelude(variables),
            "objc" | "objective-c" | "objectivec" => ObjCBridge::generate_prelude(variables),
            _ => String::new(),
        };

        if prelude.is_empty() {
            user_code.to_string()
        } else {
            format!("{}{}", prelude, user_code)
        }
    }
}
