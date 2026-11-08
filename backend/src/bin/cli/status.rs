//! MicroCode CLI — Git status with AI summaries

use std::path::Path;
use anyhow::Result;

pub async fn show_status(workspace: &Path) -> Result<()> {
    // Git status
    let output = tokio::process::Command::new("git")
        .args(["status", "--short"])
        .current_dir(workspace)
        .output()
        .await?;
    
    let status = String::from_utf8_lossy(&output.stdout);
    
    if status.is_empty() {
        println!("✓ Working tree clean");
    } else {
        println!("📋 Modified files:");
        for line in status.lines() {
            let (icon, color) = match &line[..2] {
                "M " | " M" => ("●", "\x1b[33m"),  // Modified
                "A " => ("✚", "\x1b[32m"),          // Added
                "D " | " D" => ("✖", "\x1b[31m"),   // Deleted
                "??" => ("?", "\x1b[90m"),           // Untracked
                _ => ("·", "\x1b[0m"),
            };
            println!("  {}{} {}\x1b[0m", color, icon, &line[3..]);
        }
    }
    
    // Branch info
    let branch = tokio::process::Command::new("git")
        .args(["branch", "--show-current"])
        .current_dir(workspace)
        .output()
        .await?;
    
    println!("\n🌿 Branch: {}", String::from_utf8_lossy(&branch.stdout).trim());
    
    Ok(())
}
