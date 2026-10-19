use portable_pty::{CommandBuilder, MasterPty, NativePtySystem, PtySize, PtySystem};
use std::collections::HashMap;
use std::io::Write;
use std::sync::{Arc, Mutex};
use tokio::sync::broadcast;
use uuid::Uuid;

pub struct TerminalSession {
    pub id: String,
    pub pty_master: Box<dyn portable_pty::MasterPty + Send>,
    pub writer: Box<dyn Write + Send>,
    pub tx: broadcast::Sender<Vec<u8>>,
    pub child: Arc<Mutex<Box<dyn portable_pty::Child + Send + Sync>>>,
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

        let mut cmd = CommandBuilder::new(std::env::var("SHELL").unwrap_or("bash".to_string()));
        cmd.env_remove("MICROCODE_LOCAL_API_TOKEN");
        let pair = pty_system.openpty(size)?;

        let child = pair.slave.spawn_command(cmd)?;
        let shared_child = Arc::new(Mutex::new(child));
        let thread_child = shared_child.clone();

        // Clone reader and take writer from master PTY
        let mut reader = pair.master.try_clone_reader()?;
        let writer = pair.master.take_writer()?;
        let (tx, _) = broadcast::channel(2048);
        let tx_clone = tx.clone();

        std::thread::spawn(move || {
            let mut buf = [0u8; 16384];
            while let Ok(n) = reader.read(&mut buf) {
                if n == 0 {
                    break;
                }
                let _ = tx_clone.send(buf[..n].to_vec());
            }
            if let Ok(mut c) = thread_child.lock() {
                let _ = c.wait();
            }
        });

        let id = Uuid::new_v4().to_string();
        let session = TerminalSession {
            id: id.clone(),
            pty_master: pair.master,
            writer,
            tx,
            child: shared_child,
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

    pub fn write(&self, id: &str, data: &[u8]) -> Result<(), anyhow::Error> {
        let mut sessions = self.sessions.lock().unwrap();
        if let Some(session) = sessions.get_mut(id) {
            session.writer.write_all(data)?;
            session.writer.flush()?;
        }
        Ok(())
    }

    pub fn close_session(&self, id: &str) {
        let mut sessions = self.sessions.lock().unwrap();
        if let Some(session) = sessions.remove(id) {
            if let Ok(mut child) = session.child.lock() {
                let _ = child.kill();
            }
        }
    }

    pub fn subscribe(&self, id: &str) -> Option<broadcast::Receiver<Vec<u8>>> {
        let sessions = self.sessions.lock().unwrap();
        sessions.get(id).map(|s| s.tx.subscribe())
    }
}
