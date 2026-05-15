//
//  kernel/mod.rs
//  MicroCode Kernel
//
//  The central nervous system of MicroCode.
//  Coordinates FS, Network, Power, and Safety subsystems.
//

pub mod fs;
pub mod net;
pub mod power;
pub mod safety;

use std::sync::Arc;
use tokio::sync::Mutex;

#[derive(Clone)]
pub struct Kernel {
    pub fs: Arc<fs::FileSystem>,
    pub net: Arc<net::NetworkManager>,
    pub power: Arc<power::PowerOptimizer>,
    pub safety: Arc<safety::AntiCrash>,
}

impl Kernel {
    pub async fn new() -> Self {
        println!("🦀 Booting MicroCode Kernel...");

        let safety = Arc::new(safety::AntiCrash::new());
        let power = Arc::new(power::PowerOptimizer::new());
        let fs = Arc::new(fs::FileSystem::new());
        let net = Arc::new(net::NetworkManager::new());

        // Start subsystems
        power.start_monitoring();
        safety.start_watchdog();

        println!("✅ Kernel Booted Successfully.");

        Self {
            fs,
            net,
            power,
            safety,
        }
    }

    pub async fn shutdown(&self) {
        println!("🛑 Kernel Shutting Down...");
        // Graceful shutdown logic here
    }
}
