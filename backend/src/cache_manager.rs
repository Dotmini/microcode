use std::path::{PathBuf};
use walkdir::WalkDir;
use std::fs;
use serde::{Serialize, Deserialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct DerivedDataInfo {
    pub path: String,
    pub size_bytes: u64,
    pub folder_count: usize,
    pub files_cleaned: Option<usize>,
}

pub fn get_derived_data_path() -> Option<PathBuf> {
    dirs::home_dir().map(|h| h.join("Library/Developer/Xcode/DerivedData"))
}

pub fn get_derived_data_info() -> Result<DerivedDataInfo, std::io::Error> {
    let path = match get_derived_data_path() {
        Some(p) => p,
        None => return Err(std::io::Error::new(std::io::ErrorKind::NotFound, "Home directory not found")),
    };

    if !path.exists() {
        return Ok(DerivedDataInfo {
            path: path.to_string_lossy().into_owned(),
            size_bytes: 0,
            folder_count: 0,
            files_cleaned: None,
        });
    }

    let mut size_bytes = 0;
    let mut folder_count = 0;

    for entry in WalkDir::new(&path).into_iter().filter_map(|e| e.ok()) {
        if let Ok(metadata) = entry.metadata() {
            if metadata.is_file() {
                size_bytes += metadata.len();
            } else if metadata.is_dir() && entry.path() != path {
                folder_count += 1;
            }
        }
    }

    Ok(DerivedDataInfo {
        path: path.to_string_lossy().into_owned(),
        size_bytes,
        folder_count,
        files_cleaned: None,
    })
}

pub fn clear_derived_data(project_pattern: Option<String>) -> Result<DerivedDataInfo, std::io::Error> {
    let path = match get_derived_data_path() {
        Some(p) => p,
        None => return Err(std::io::Error::new(std::io::ErrorKind::NotFound, "Home directory not found")),
    };

    if !path.exists() {
        return Ok(DerivedDataInfo {
            path: path.to_string_lossy().into_owned(),
            size_bytes: 0,
            folder_count: 0,
            files_cleaned: Some(0),
        });
    }

    let mut files_cleaned = 0;

    if let Some(pattern) = project_pattern {
        // Clear specific folders matching pattern (e.g. MyProject-axvyw...)
        if !pattern.trim().is_empty() {
            let pattern_lower = pattern.to_lowercase();
            if let Ok(entries) = fs::read_dir(&path) {
                for entry in entries.filter_map(|e| e.ok()) {
                    let name = entry.file_name().to_string_lossy().to_lowercase();
                    if name.starts_with(&pattern_lower) {
                        let folder_path = entry.path();
                        if folder_path.is_dir() {
                            if fs::remove_dir_all(&folder_path).is_ok() {
                                files_cleaned += 1;
                            }
                        }
                    }
                }
            }
        }
    } else {
        // Clear everything inside DerivedData
        if let Ok(entries) = fs::read_dir(&path) {
            for entry in entries.filter_map(|e| e.ok()) {
                let entry_path = entry.path();
                if entry_path.is_dir() {
                    if fs::remove_dir_all(&entry_path).is_ok() {
                        files_cleaned += 1;
                    }
                } else if entry_path.is_file() {
                    if fs::remove_file(&entry_path).is_ok() {
                        files_cleaned += 1;
                    }
                }
            }
        }
    }

    // Recalculate size after deletion
    let new_info = get_derived_data_info()?;
    Ok(DerivedDataInfo {
        path: new_info.path,
        size_bytes: new_info.size_bytes,
        folder_count: new_info.folder_count,
        files_cleaned: Some(files_cleaned),
    })
}
