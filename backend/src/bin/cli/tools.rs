//! MicroCode CLI — Tool definitions (re-exports for CLI context)

// This module provides CLI-specific tool wrappers.
// The actual tool implementations are in agent_loop.rs.
// Future: This will be refactored to share tool implementations
// with the backend via microcode_embedded crate.

pub const CORE_TOOLS: &[&str] = &[
    "file_read", "file_write", "replace_in_file",
    "grep_search", "shell", "git_status",
];

pub const NAVIGATION_TOOLS: &[&str] = &[
    "find_symbol", "list_directory_tree", "file_search",
    "multi_file_read", "git_diff", "git_log",
];

pub const ALL_TOOLS: &[&str] = &[
    "file_read", "file_write", "replace_in_file",
    "grep_search", "shell", "git_status",
    "find_symbol", "list_directory_tree", "file_search",
    "multi_file_read", "git_diff", "git_log",
    "patch_file", "create_directory", "rename_file",
];
