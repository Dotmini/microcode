//! MicroCode CLI — Session management

use std::path::Path;
use anyhow::Result;

pub fn compact_history(_workspace: &Path) -> Result<()> {
    // TODO: Load session, summarize with AI, save compacted version
    Ok(())
}
