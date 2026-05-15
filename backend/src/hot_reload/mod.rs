//! Hot Reload Engine - Xcode-like Dynamic Replacement System
//!
//! This module implements:
//! - Thunk table for function pointer indirection
//! - Runtime swizzling for memory-level patching
//! - Preview agent for isolated rendering
//! - High-performance IPC (Unix sockets + shared memory)
//! - State preservation across reloads

pub mod agent;
pub mod ipc;
pub mod state;
pub mod swizzle;
pub mod thunk;

pub use agent::PreviewAgent;
pub use ipc::{IPCMessage, IPCServer};
pub use state::StateStorage;
pub use swizzle::Swizzler;
pub use thunk::ThunkTable;
