//! File operations module
//!
//! Provides async file system operations for reading, writing, and listing files

use crate::error::{AppError, Result};
use crate::models::FileInfo;
use std::path::Path;
use tokio::fs;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use walkdir::WalkDir;

/// List files and directories in a given path
pub async fn list_directory(path: &str) -> Result<Vec<FileInfo>> {
    let path_buf = Path::new(path);

    if !path_buf.exists() {
        return Err(AppError::FileNotFound(path.to_string()));
    }

    if !path_buf.is_dir() {
        return Err(AppError::BadRequest(format!(
            "Path is not a directory: {}",
            path
        )));
    }

    let mut files = Vec::new();

    let entries = fs::read_dir(path).await?;
    let mut entries = entries;

    while let Some(entry) = entries.next_entry().await? {
        let path = entry.path();
        let metadata = entry.metadata().await?;

        let file_info = FileInfo {
            name: entry
                .file_name()
                .to_string_lossy()
                .to_string(),
            path: path.to_string_lossy().to_string(),
            is_directory: metadata.is_dir(),
            size: metadata.len(),
            modified: metadata
                .modified()
                .ok()
                .and_then(|time| {
                    time.duration_since(std::time::UNIX_EPOCH)
                        .ok()
                        .map(|d| {
                            chrono::DateTime::from_timestamp(d.as_secs() as i64, 0)
                                .map(|dt| dt.to_rfc3339())
                                .unwrap_or_default()
                        })
                }),
            extension: path
                .extension()
                .and_then(|ext| ext.to_str())
                .map(|s| s.to_string()),
        };

        files.push(file_info);
    }

    // Sort: directories first, then by name
    files.sort_by(|a, b| {
        match (a.is_directory, b.is_directory) {
            (true, false) => std::cmp::Ordering::Less,
            (false, true) => std::cmp::Ordering::Greater,
            _ => a.name.to_lowercase().cmp(&b.name.to_lowercase()),
        }
    });

    Ok(files)
}

/// List files recursively
pub async fn list_directory_recursive(path: &str) -> Result<Vec<FileInfo>> {
    let path_buf = Path::new(path);

    if !path_buf.exists() {
        return Err(AppError::FileNotFound(path.to_string()));
    }

    if !path_buf.is_dir() {
        return Err(AppError::BadRequest(format!(
            "Path is not a directory: {}",
            path
        )));
    }

    let mut files = Vec::new();

    for entry in WalkDir::new(path).follow_links(false) {
        let entry = entry.map_err(|e| AppError::IoError(std::io::Error::new(
            std::io::ErrorKind::Other,
            e.to_string(),
        )))?;

        let path = entry.path();
        let metadata = entry.metadata().map_err(|e| AppError::IoError(std::io::Error::new(
            std::io::ErrorKind::Other,
            e.to_string(),
        )))?;

        let file_info = FileInfo {
            name: entry
                .file_name()
                .to_string_lossy()
                .to_string(),
            path: path.to_string_lossy().to_string(),
            is_directory: metadata.is_dir(),
            size: metadata.len(),
            modified: metadata
                .modified()
                .ok()
                .and_then(|time| {
                    time.duration_since(std::time::UNIX_EPOCH)
                        .ok()
                        .map(|d| {
                            chrono::DateTime::from_timestamp(d.as_secs() as i64, 0)
                                .map(|dt| dt.to_rfc3339())
                                .unwrap_or_default()
                        })
                }),
            extension: path
                .extension()
                .and_then(|ext| ext.to_str())
                .map(|s| s.to_string()),
        };

        files.push(file_info);
    }

    Ok(files)
}

/// Read file contents
pub async fn read_file(path: &str) -> Result<String> {
    let path_buf = Path::new(path);

    if !path_buf.exists() {
        return Err(AppError::FileNotFound(path.to_string()));
    }

    if !path_buf.is_file() {
        return Err(AppError::BadRequest(format!(
            "Path is not a file: {}",
            path
        )));
    }

    let mut file = fs::File::open(path).await.map_err(|e| {
        AppError::FileReadError(format!("Failed to open file {}: {}", path, e))
    })?;

    let mut contents = String::new();
    file.read_to_string(&mut contents).await.map_err(|e| {
        AppError::FileReadError(format!("Failed to read file {}: {}", path, e))
    })?;

    Ok(contents)
}

/// Write file contents
pub async fn write_file(path: &str, content: &str) -> Result<()> {
    let path_buf = Path::new(path);

    // Create parent directories if they don't exist
    if let Some(parent) = path_buf.parent() {
        if !parent.exists() {
            fs::create_dir_all(parent).await.map_err(|e| {
                AppError::FileWriteError(format!(
                    "Failed to create parent directories for {}: {}",
                    path, e
                ))
            })?;
        }
    }

    let mut file = fs::File::create(path).await.map_err(|e| {
        AppError::FileWriteError(format!("Failed to create file {}: {}", path, e))
    })?;

    file.write_all(content.as_bytes()).await.map_err(|e| {
        AppError::FileWriteError(format!("Failed to write to file {}: {}", path, e))
    })?;

    file.sync_all().await.map_err(|e| {
        AppError::FileWriteError(format!("Failed to sync file {}: {}", path, e))
    })?;

    Ok(())
}

/// Delete a file or directory
pub async fn delete_file(path: &str) -> Result<()> {
    let path_buf = Path::new(path);

    if !path_buf.exists() {
        return Err(AppError::FileNotFound(path.to_string()));
    }

    if path_buf.is_dir() {
        fs::remove_dir_all(path).await.map_err(|e| {
            AppError::IoError(e)
        })?;
    } else {
        fs::remove_file(path).await.map_err(|e| {
            AppError::IoError(e)
        })?;
    }

    Ok(())
}

/// Create a new directory
pub async fn create_directory(path: &str) -> Result<()> {
    fs::create_dir_all(path).await.map_err(|e| {
        AppError::IoError(e)
    })?;

    Ok(())
}

/// Check if a path exists
pub async fn exists(path: &str) -> bool {
    Path::new(path).exists()
}

/// Check if a path is a directory
pub async fn is_directory(path: &str) -> bool {
    Path::new(path).is_dir()
}

/// Check if a path is a file
pub async fn is_file(path: &str) -> bool {
    Path::new(path).is_file()
}

/// Get file metadata
pub async fn get_metadata(path: &str) -> Result<FileInfo> {
    let path_buf = Path::new(path);

    if !path_buf.exists() {
        return Err(AppError::FileNotFound(path.to_string()));
    }

    let metadata = fs::metadata(path).await?;

    Ok(FileInfo {
        name: path_buf
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_default(),
        path: path.to_string(),
        is_directory: metadata.is_dir(),
        size: metadata.len(),
        modified: metadata
            .modified()
            .ok()
            .and_then(|time| {
                time.duration_since(std::time::UNIX_EPOCH)
                    .ok()
                    .map(|d| {
                        chrono::DateTime::from_timestamp(d.as_secs() as i64, 0)
                            .map(|dt| dt.to_rfc3339())
                            .unwrap_or_default()
                    })
            }),
        extension: path_buf
            .extension()
            .and_then(|ext| ext.to_str())
            .map(|s| s.to_string()),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_file_operations() {
        let temp_dir = std::env::temp_dir();
        let test_file = temp_dir.join("microcode_test.txt");
        let test_path = test_file.to_str().unwrap();

        // Write file
        write_file(test_path, "Hello, World!").await.unwrap();

        // Read file
        let content = read_file(test_path).await.unwrap();
        assert_eq!(content, "Hello, World!");

        // Check existence
        assert!(exists(test_path).await);
        assert!(is_file(test_path).await);
        assert!(!is_directory(test_path).await);

        // Get metadata
        let metadata = get_metadata(test_path).await.unwrap();
        assert_eq!(metadata.name, "microcode_test.txt");
        assert!(!metadata.is_directory);

        // Delete file
        delete_file(test_path).await.unwrap();
        assert!(!exists(test_path).await);
    }
}
