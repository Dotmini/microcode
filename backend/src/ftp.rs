use crate::models::FileInfo;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use suppaftp::AsyncFtpStream;
use suppaftp::AsyncNativeTlsFtpStream;
use tokio::sync::Mutex;
// Bridge traits
use tokio::io::AsyncReadExt;
use tokio_util::compat::{FuturesAsyncReadCompatExt, TokioAsyncReadCompatExt};

// Use root-level re-exports for public APIs
use suppaftp::AsyncNativeTlsConnector;

#[derive(Clone)]
pub struct FtpManager {
    sessions: Arc<Mutex<HashMap<String, AsyncNativeTlsFtpStream>>>,
}

impl std::fmt::Debug for FtpManager {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("FtpManager").finish()
    }
}

impl FtpManager {
    pub fn new() -> Self {
        Self {
            sessions: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub async fn connect(
        &self,
        id: &str,
        host: &str,
        port: u16,
        user: &str,
        pass: &str,
        secure: bool,
    ) -> Result<(), String> {
        let mut ftp_stream = AsyncNativeTlsFtpStream::connect(format!("{}:{}", host, port))
            .await
            .map_err(|e| format!("FTP Connection failed: {}", e))?;

        if secure {
            // According to suppaftp docs, we should use their re-exports
            let connector = suppaftp::async_native_tls::TlsConnector::new();
            let async_connector = AsyncNativeTlsConnector::from(connector);

            ftp_stream = ftp_stream
                .into_secure(async_connector, host)
                .await
                .map_err(|e: suppaftp::FtpError| format!("FTP Secure upgrade failed: {}", e))?;
        }

        ftp_stream
            .login(user, pass)
            .await
            .map_err(|e| format!("FTP Login failed: {}", e))?;

        self.sessions
            .lock()
            .await
            .insert(id.to_string(), ftp_stream);
        Ok(())
    }

    pub async fn list_files(&self, id: &str, path: &str) -> Result<Vec<FileInfo>, String> {
        let mut sessions = self.sessions.lock().await;
        if let Some(ftp) = sessions.get_mut(id) {
            ftp.cwd(path)
                .await
                .map_err(|e: suppaftp::FtpError| e.to_string())?;
            let list = ftp
                .list(None)
                .await
                .map_err(|e: suppaftp::FtpError| e.to_string())?;

            let mut files = Vec::new();
            for entry_raw in list {
                let name = entry_raw
                    .split_whitespace()
                    .last()
                    .unwrap_or(&entry_raw)
                    .to_string();
                files.push(FileInfo {
                    name: name.clone(),
                    path: format!("{}/{}", path.trim_end_matches('/'), name),
                    is_directory: entry_raw.starts_with('d'),
                    extension: std::path::Path::new(&name)
                        .extension()
                        .map(|s| s.to_string_lossy().to_string()),
                    modified: None,
                    size: 0,
                });
            }
            Ok(files)
        } else {
            Err("FTP Session not found".to_string())
        }
    }

    pub async fn upload_file(&self, id: &str, path: &str, content: &[u8]) -> Result<(), String> {
        let mut sessions = self.sessions.lock().await;
        if let Some(ftp) = sessions.get_mut(id) {
            let async_cursor = std::io::Cursor::new(content.to_vec());
            // std::io::Cursor needs TokioAsyncReadCompatExt to become an AsyncRead
            let mut compat_cursor = async_cursor.compat();
            // suppaftp 5.4 uses put_file
            ftp.put_file(path, &mut compat_cursor)
                .await
                .map_err(|e: suppaftp::FtpError| e.to_string())?;
            Ok(())
        } else {
            Err("FTP Session not found".to_string())
        }
    }

    pub async fn download_file(&self, id: &str, path: &str) -> Result<Vec<u8>, String> {
        let mut sessions = self.sessions.lock().await;
        if let Some(ftp) = sessions.get_mut(id) {
            let cursor = ftp
                .retr_as_stream(path)
                .await
                .map_err(|e: suppaftp::FtpError| e.to_string())?;
            let mut data = Vec::new();
            // suppaftp stream (futures::AsyncRead) needs FuturesAsyncReadCompatExt to become tokio's AsyncRead
            let mut compat_reader = cursor.compat();
            compat_reader
                .read_to_end(&mut data)
                .await
                .map_err(|e: std::io::Error| e.to_string())?;
            Ok(data)
        } else {
            Err("FTP Session not found".to_string())
        }
    }

    pub async fn mkdir(&self, id: &str, path: &str) -> Result<(), String> {
        let mut sessions = self.sessions.lock().await;
        if let Some(ftp) = sessions.get_mut(id) {
            ftp.mkdir(path)
                .await
                .map_err(|e: suppaftp::FtpError| e.to_string())?;
            Ok(())
        } else {
            Err("FTP Session not found".to_string())
        }
    }

    pub async fn rename(&self, id: &str, source: &str, destination: &str) -> Result<(), String> {
        let mut sessions = self.sessions.lock().await;
        if let Some(ftp) = sessions.get_mut(id) {
            ftp.rename(source, destination)
                .await
                .map_err(|e: suppaftp::FtpError| e.to_string())?;
            Ok(())
        } else {
            Err("FTP Session not found".to_string())
        }
    }

    pub async fn remove_file(&self, id: &str, path: &str) -> Result<(), String> {
        let mut sessions = self.sessions.lock().await;
        if let Some(ftp) = sessions.get_mut(id) {
            ftp.rm(path)
                .await
                .map_err(|e: suppaftp::FtpError| e.to_string())?;
            Ok(())
        } else {
            Err("FTP Session not found".to_string())
        }
    }

    pub async fn remove_dir(&self, id: &str, path: &str) -> Result<(), String> {
        let mut sessions = self.sessions.lock().await;
        if let Some(ftp) = sessions.get_mut(id) {
            ftp.rmdir(path)
                .await
                .map_err(|e: suppaftp::FtpError| e.to_string())?;
            Ok(())
        } else {
            Err("FTP Session not found".to_string())
        }
    }

    pub async fn disconnect(&self, id: &str) {
        let mut sessions = self.sessions.lock().await;
        if let Some(mut ftp) = sessions.remove(id) {
            let _ = ftp.quit().await;
        }
    }
}
