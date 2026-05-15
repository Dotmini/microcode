//! Live Preview Module
//!
//! Hot-reload system for real-time code preview.
//! Similar to Xcode's SwiftUI Canvas.

pub mod host;
pub mod ipc;

pub use host::PreviewHost;
pub use ipc::{PreviewMessage, PreviewServer};
