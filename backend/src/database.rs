use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::{
    mysql::MySqlPoolOptions, postgres::PgPoolOptions, sqlite::SqlitePoolOptions, Column,
    Connection, Executor, Row, TypeInfo,
};
use sqlx::{MySqlPool, PgPool, SqlitePool};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;
use uuid::Uuid;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub enum DatabaseType {
    SQLite,
    PostgreSQL,
    MySQL,
}

#[derive(Clone)]
pub enum DbPool {
    SQLite(SqlitePool),
    Postgres(PgPool),
    MySQL(MySqlPool),
}

pub struct DatabaseManager {
    pools: Arc<Mutex<HashMap<String, DbPool>>>,
}

#[derive(Serialize)]
pub struct QueryResult {
    pub columns: Vec<String>,
    pub rows: Vec<Vec<Value>>,
    pub affected_rows: u64,
}

impl DatabaseManager {
    pub fn new() -> Self {
        Self {
            pools: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub async fn connect(&self, db_type: DatabaseType, connection_string: &str) -> Result<String> {
        let pool = match db_type {
            DatabaseType::SQLite => {
                let pool = SqlitePoolOptions::new()
                    .connect(connection_string)
                    .await
                    .map_err(|e| anyhow!("Failed to connect to SQLite: {}", e))?;
                DbPool::SQLite(pool)
            }
            DatabaseType::PostgreSQL => {
                let pool = PgPoolOptions::new()
                    .connect(connection_string)
                    .await
                    .map_err(|e| anyhow!("Failed to connect to PostgreSQL: {}", e))?;
                DbPool::Postgres(pool)
            }
            DatabaseType::MySQL => {
                let pool = MySqlPoolOptions::new()
                    .connect(connection_string)
                    .await
                    .map_err(|e| anyhow!("Failed to connect to MySQL: {}", e))?;
                DbPool::MySQL(pool)
            }
        };

        let id = Uuid::new_v4().to_string();
        self.pools.lock().await.insert(id.clone(), pool);
        Ok(id)
    }

    pub async fn disconnect(&self, connection_id: &str) -> Result<()> {
        let mut pools = self.pools.lock().await;
        if pools.remove(connection_id).is_some() {
            Ok(())
        } else {
            Err(anyhow!("Connection ID not found"))
        }
    }

    pub async fn execute_query(&self, connection_id: &str, query: &str) -> Result<QueryResult> {
        let pools = self.pools.lock().await;
        let pool = pools
            .get(connection_id)
            .ok_or_else(|| anyhow!("Connection ID not found"))?;

        let (columns, rows) = match pool {
            DbPool::SQLite(p) => {
                let result = sqlx::query::<sqlx::Sqlite>(query)
                    .fetch_all(p)
                    .await
                    .map_err(|e| anyhow!("Query failed: {}", e))?;

                if result.is_empty() {
                    return Ok(QueryResult {
                        columns: vec![],
                        rows: vec![],
                        affected_rows: 0,
                    });
                }

                let columns: Vec<String> = result[0]
                    .columns()
                    .iter()
                    .map(|c| c.name().to_string())
                    .collect();
                let mut data = Vec::new();

                for row in result {
                    let mut row_values = Vec::new();
                    for (i, _) in columns.iter().enumerate() {
                        let val = if let Ok(s) = row.try_get::<String, _>(i) {
                            Value::String(s)
                        } else if let Ok(n) = row.try_get::<i64, _>(i) {
                            Value::Number(n.into())
                        } else if let Ok(f) = row.try_get::<f64, _>(i) {
                            serde_json::Number::from_f64(f)
                                .map(Value::Number)
                                .unwrap_or(Value::Null)
                        } else {
                            Value::Null
                        };
                        row_values.push(val);
                    }
                    data.push(row_values);
                }
                (columns, data)
            }
            DbPool::Postgres(p) => {
                let result = sqlx::query::<sqlx::Postgres>(query)
                    .fetch_all(p)
                    .await
                    .map_err(|e| anyhow!("Query failed: {}", e))?;

                if result.is_empty() {
                    return Ok(QueryResult {
                        columns: vec![],
                        rows: vec![],
                        affected_rows: 0,
                    });
                }

                let columns: Vec<String> = result[0]
                    .columns()
                    .iter()
                    .map(|c| c.name().to_string())
                    .collect();
                let mut data = Vec::new();

                for row in result {
                    let mut row_values = Vec::new();
                    for (i, _) in columns.iter().enumerate() {
                        let val = if let Ok(s) = row.try_get::<String, _>(i) {
                            Value::String(s)
                        } else if let Ok(n) = row.try_get::<i64, _>(i) {
                            Value::Number(n.into())
                        } else {
                            Value::Null
                        };
                        row_values.push(val);
                    }
                    data.push(row_values);
                }
                (columns, data)
            }
            DbPool::MySQL(p) => {
                let result = sqlx::query::<sqlx::MySql>(query)
                    .fetch_all(p)
                    .await
                    .map_err(|e| anyhow!("Query failed: {}", e))?;

                if result.is_empty() {
                    return Ok(QueryResult {
                        columns: vec![],
                        rows: vec![],
                        affected_rows: 0,
                    });
                }

                let columns: Vec<String> = result[0]
                    .columns()
                    .iter()
                    .map(|c| c.name().to_string())
                    .collect();
                let mut data = Vec::new();

                for row in result {
                    let mut row_values = Vec::new();
                    for (i, _) in columns.iter().enumerate() {
                        let val = if let Ok(s) = row.try_get::<String, _>(i) {
                            Value::String(s)
                        } else if let Ok(n) = row.try_get::<i64, _>(i) {
                            Value::Number(n.into())
                        } else {
                            Value::Null
                        };
                        row_values.push(val);
                    }
                    data.push(row_values);
                }
                (columns, data)
            }
        };

        Ok(QueryResult {
            columns,
            rows,
            affected_rows: 0,
        })
    }
}
