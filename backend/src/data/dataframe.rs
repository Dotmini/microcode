use crate::error::{AppError, Result};
use polars::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;
use std::sync::{Arc, Mutex};
use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct DataFrameManager {
    dfs: Arc<Mutex<HashMap<String, DataFrame>>>,
    named_dfs: Arc<Mutex<HashMap<String, DataFrame>>>,
}

impl DataFrameManager {
    pub fn new() -> Self {
        Self {
            dfs: Arc::new(Mutex::new(HashMap::new())),
            named_dfs: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub fn store_named(&self, name: String, df: DataFrame) {
        self.named_dfs.lock().unwrap().insert(name, df);
    }

    pub fn get_named(&self, name: &str) -> Option<DataFrame> {
        self.named_dfs.lock().unwrap().get(name).cloned()
    }

    pub fn list_named(&self) -> Vec<String> {
        self.named_dfs.lock().unwrap().keys().cloned().collect()
    }

    pub fn load_file(&self, path: &str) -> Result<String> {
        let path = Path::new(path);
        if !path.exists() {
            return Err(AppError::FileNotFound(path.to_string_lossy().to_string()));
        }

        let extension = path.extension().and_then(|s| s.to_str()).unwrap_or("");

        let df = match extension {
            "csv" => CsvReader::from_path(path)
                .map_err(|e| AppError::DataFrameError(e.to_string()))?
                .has_header(true)
                .finish()
                .map_err(|e| AppError::DataFrameError(e.to_string()))?,
            "parquet" => {
                ParquetReader::new(std::fs::File::open(path).map_err(|e| AppError::IoError(e))?)
                    .finish()
                    .map_err(|e| AppError::DataFrameError(e.to_string()))?
            }
            "json" => JsonReader::new(std::fs::File::open(path).map_err(|e| AppError::IoError(e))?)
                .finish()
                .map_err(|e| AppError::DataFrameError(e.to_string()))?,
            _ => return Err(AppError::BadRequest("Unsupported file format".to_string())),
        };

        let id = Uuid::new_v4().to_string();
        self.dfs.lock().unwrap().insert(id.clone(), df);
        Ok(id)
    }

    pub fn get_slice(&self, id: &str, offset: i64, limit: usize) -> Result<serde_json::Value> {
        let dfs = self.dfs.lock().unwrap();
        let df = dfs
            .get(id)
            .ok_or_else(|| AppError::NotFound("DataFrame not found".to_string()))?;

        let sliced = df.slice(offset, limit);

        // Convert to JSON
        let json_str =
            serde_json::to_string(&sliced).map_err(|e| AppError::DataFrameError(e.to_string()))?;
        // Polars serializes to a string, or we can use JsonWriter.
        // Actually, DataFrame struct doesn't impl Serialize directly in a way we might want for API.
        // Let's use write_json to memory.

        let mut buf = Vec::new();
        JsonWriter::new(&mut buf)
            .with_json_format(JsonFormat::Json)
            .finish(&mut sliced.clone())
            .map_err(|e| AppError::DataFrameError(e.to_string()))?;

        let json_val: serde_json::Value = serde_json::from_slice(&buf)
            .map_err(|e| AppError::SerializationError(e.to_string()))?;

        Ok(json_val)
    }

    pub fn get_schema(&self, id: &str) -> Result<HashMap<String, String>> {
        let dfs = self.dfs.lock().unwrap();
        let df = dfs
            .get(id)
            .ok_or_else(|| AppError::NotFound("DataFrame not found".to_string()))?;

        let schema = df.schema();
        let mut result = HashMap::new();

        for (name, dtype) in schema.iter() {
            result.insert(name.to_string(), dtype.to_string());
        }

        Ok(result)
    }
}
