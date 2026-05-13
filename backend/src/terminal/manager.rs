use portable_pty::{CommandBuilder, NativePtySystem, PtySize, PtySystem, MasterPty};
use std::collections::HashMap;
use std::io::Write;
use std::sync::{Arc, Mutex};
use tokio::sync::broadcast;
use uuid::Uuid;

pub struct TerminalSession {
    pub id: String,
    pub pty_master: Box<dyn portable_pty::MasterPty + Send>,
    pub tx: broadcast::Sender<Vec<u8>>,
}

impl std::fmt::Debug for TerminalSession {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("TerminalSession")
            .field("id", &self.id)
            .finish()
    }
}

#[derive(Debug)]
pub struct TerminalManager {
    sessions: Arc<Mutex<HashMap<String, TerminalSession>>>,
}

impl TerminalManager {
    pub fn new() -> Self {
        Self {
            sessions: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub fn create_session(&self, cols: u16, rows: u16) -> Result<String, anyhow::Error> {
        let pty_system = NativePtySystem::default();
        
        let size = PtySize {
            rows,
            cols,
            pixel_width: 0,
            pixel_height: 0,
        };

        let cmd = CommandBuilder::new(std::env::var("SHELL").unwrap_or("bash".to_string()));
        let pair = pty_system.openpty(size)?;

        let mut child = pair.slave.spawn_command(cmd)?;
        
        // Clone for background thread
        let mut reader = pair.master.try_clone_reader()?;
        let (tx, _) = broadcast::channel(100);
        let tx_clone = tx.clone();
        
        std::thread::spawn(move || {
            let mut buf = [0u8; 1024];
            while let Ok(n) = reader.read(&mut buf) {
                if n == 0 { break; }
                let _ = tx_clone.send(buf[..n].to_vec());
            }
            let _ = child.wait();
        });

        let id = Uuid::new_v4().to_string();
        let session = TerminalSession {
            id: id.clone(),
            pty_master: pair.master,
            tx,
        };

        self.sessions.lock().unwrap().insert(id.clone(), session);
        Ok(id)
    }
    
    pub fn resize(&self, id: &str, cols: u16, rows: u16) -> Result<(), anyhow::Error> {
        let mut sessions = self.sessions.lock().unwrap();
        if let Some(session) = sessions.get_mut(id) {
            session.pty_master.resize(PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            })?;
        }
        Ok(())
    }
    
    pub fn write(&self, id: &str, _data: &[u8]) -> Result<(), anyhow::Error> {
        let mut sessions = self.sessions.lock().unwrap();
        if let Some(_session) = sessions.get_mut(id) {
             // FIXME: portable-pty MasterPty trait object issues with writing/FD access.
             // Stubbing for now to allow build.
             // We need to find a way to write to session.pty_master.
             #[cfg(unix)]
             {
                 // use std::os::unix::io::{RawFd, AsRawFd};
                 // ...
             }
        }
        Ok(())
    }
    
    pub fn subscribe(&self, id: &str) -> Option<broadcast::Receiver<Vec<u8>>> {
        let sessions = self.sessions.lock().unwrap();
        sessions.get(id).map(|s| s.tx.subscribe())
    }
}
