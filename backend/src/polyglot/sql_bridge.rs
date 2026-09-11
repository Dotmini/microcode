//! SQL / DuckDB Polyglot In-Memory Bridge
//!
//! Allows executing standard SQL directly on active Arrow SHM variables
//! with zero-copy table registration.

use crate::arrow_cdata::deserialize_df_from_arrow_ipc;
use crate::error::{AppError, Result};
use crate::shm_broker::GLOBAL_SHM_BROKER;
use polars::prelude::*;
use polars::sql::SQLContext;
use std::sync::Arc;

pub struct SqlBridge;

impl SqlBridge {
    /// Execute a SQL query directly against active in-memory Arrow tables in a session
    pub fn execute_sql(session_id: &str, query: &str) -> Result<DataFrame> {
        let mut ctx = SQLContext::new();
        let broker = &*GLOBAL_SHM_BROKER;
        let vars = broker.list_session_variables(session_id);

        for v in vars {
            if let Some(seg_arc) = broker.get(session_id, &v.name) {
                if let Ok(seg) = seg_arc.read() {
                    if let Ok(slice) = seg.read_slice(0, seg.size()) {
                        // Attempt to deserialize as Polars DataFrame
                        if let Ok(df) = deserialize_df_from_arrow_ipc(slice) {
                            let lf = df.lazy();
                            ctx.register(&v.name, lf);
                        }
                    }
                }
            }
        }

        // Also register any /tmp/*.shm dataframes created by MicroCode SHM
        if let Ok(entries) = std::fs::read_dir("/tmp") {
            for entry in entries.flatten() {
                let path = entry.path();
                if let Some(ext) = path.extension() {
                    if ext == "shm" {
                        if let Some(stem) = path.file_stem().and_then(|s| s.to_str()) {
                            if let Ok(file) = std::fs::File::open(&path) {
                                use polars::prelude::SerReader;
                                if let Ok(df) = polars::prelude::ParquetReader::new(file).finish() {
                                    ctx.register(stem, df.lazy());
                                }
                            }
                        }
                    }
                }
            }
        }

        let res_lf = ctx
            .execute(query)
            .map_err(|e| AppError::InternalError(format!("SQL Execution failed: {}", e)))?;

        let res_df = res_lf
            .collect()
            .map_err(|e| AppError::InternalError(format!("Failed to collect SQL result: {}", e)))?;

        Ok(res_df)
    }
}
