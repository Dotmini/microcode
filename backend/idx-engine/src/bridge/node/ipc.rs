use serde_json::Value;
use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{Child, Command}; // Added use to make it compile

pub struct NodeBridge {
    process: Child,
}

impl NodeBridge {
    pub fn new(script_path: &str) -> anyhow::Result<Self> {
        let process = Command::new("node")
            .arg(script_path)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()?;

        Ok(Self { process })
    }

    // Placeholder for loop
    pub async fn start_loop(&mut self) -> anyhow::Result<()> {
        Ok(())
    }
}
