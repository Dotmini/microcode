//! MicroCode CLI — Cost reporting

use std::path::Path;
use anyhow::Result;

pub fn show_cost_report(_workspace: &Path) -> Result<()> {
    // TODO: Read from persistent session store
    println!("╔══════════════════════════════════════╗");
    println!("║   MicroCode CLI — Cost Report        ║");
    println!("╠══════════════════════════════════════╣");
    println!("║ Session tokens:        0             ║");
    println!("║ Estimated cost:        $0.0000       ║");
    println!("║ Local model savings:   $0.0000       ║");
    println!("╚══════════════════════════════════════╝");
    Ok(())
}
