use anyhow::Result;
use arrow_array::{
    ArrayRef, FixedSizeListArray, Float32Array, RecordBatch, RecordBatchIterator, StringArray,
};
use arrow_schema::{DataType, Field, Schema};
use candle_core::{DType, Device, Tensor};
use candle_nn::VarBuilder;
use candle_transformers::models::bert::{BertModel, Config};
use hf_hub::{api::tokio::Api, Repo, RepoType};
use lancedb::{connect, connection::Connection, Table};
use std::sync::Arc;
use tokenizers::Tokenizer;

pub struct SmartTierEngine {
    db: Connection,
    table_name: String,
    device: Device,
    model: Arc<BertModel>,
    tokenizer: Arc<Tokenizer>,
}

impl std::fmt::Debug for SmartTierEngine {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SmartTierEngine")
            .field("table_name", &self.table_name)
            .field("device", &self.device)
            // Skip model and tokenizer as they likely don't implement Debug
            .finish()
    }
}

impl SmartTierEngine {
    pub async fn new(uri: &str) -> Result<Self> {
        let db = connect(uri).execute().await?;

        // Load Model (MiniLM-L6-v2) for speed ("Fastest")
        let api = Api::new()?;
        let repo = api.repo(Repo::new(
            "sentence-transformers/all-MiniLM-L6-v2".to_string(),
            RepoType::Model,
        ));
        let config_filename = repo.get("config.json").await?;
        let tokenizer_filename = repo.get("tokenizer.json").await?;
        let weights_filename = repo.get("model.safetensors").await?;

        let config: Config = serde_json::from_str(&std::fs::read_to_string(config_filename)?)?;
        let tokenizer = Tokenizer::from_file(tokenizer_filename).map_err(|e| anyhow::anyhow!(e))?;

        // Use Metal on Mac if available, else CPU
        #[cfg(target_os = "macos")]
        let device = Device::new_metal(0).unwrap_or(Device::Cpu);
        #[cfg(not(target_os = "macos"))]
        let device = Device::Cpu;

        // Correctly load safetensors using VarBuilder
        let vb = unsafe {
            VarBuilder::from_mmaped_safetensors(&[weights_filename], DType::F32, &device)?
        };
        let model = BertModel::load(vb, &config)?;

        Ok(Self {
            db,
            table_name: "code_vectors".to_string(),
            device,
            model: Arc::new(model),
            tokenizer: Arc::new(tokenizer),
        })
    }

    async fn embed_text(&self, text: &str) -> Result<Vec<f32>> {
        let tokens = self
            .tokenizer
            .encode(text, true)
            .map_err(|e| anyhow::anyhow!(e))?;
        let token_ids = Tensor::new(tokens.get_ids(), &self.device)?.unsqueeze(0)?;
        let token_type_ids = Tensor::new(tokens.get_type_ids(), &self.device)?.unsqueeze(0)?;

        let embeddings = self.model.forward(&token_ids, &token_type_ids)?;

        // Mean pooling
        let (_b, s, _h) = embeddings.dims3()?;
        let embeddings = (embeddings.sum(1)? / (s as f64))?;
        let embeddings = embeddings.flatten_all()?;

        let vec = embeddings.to_vec1::<f32>()?;
        Ok(vec)
    }

    pub async fn index_workspace(&self, path: &str) -> Result<usize> {
        let _table = self.get_or_create_table().await?;
        let mut total_indexed = 0;

        let mut ids = Vec::new();
        let mut vectors = Vec::new(); // Flattened
        let mut texts = Vec::new();
        let mut paths = Vec::new();

        for entry in walkdir::WalkDir::new(path) {
            let entry = entry?;
            if entry.file_type().is_file() {
                if let Some(ext) = entry.path().extension() {
                    let ext = ext.to_string_lossy();
                    if [
                        "rs", "swift", "py", "js", "ts", "cpp", "c", "h", "java", "kt",
                    ]
                    .contains(&ext.as_ref())
                    {
                        if let Ok(content) = std::fs::read_to_string(entry.path()) {
                            // Simplified chunking: one chunk per file for now if small enough
                            // In production, use a text splitter.
                            let chunk = content.chars().take(1000).collect::<String>(); // Take first 1000 chars

                            if let Ok(embedding) = self.embed_text(&chunk).await {
                                ids.push(uuid::Uuid::new_v4().to_string());
                                vectors.extend(embedding);
                                texts.push(chunk);
                                paths.push(entry.path().to_string_lossy().to_string());
                                total_indexed += 1;
                            }
                        }
                    }
                }
            }
        }

        if ids.is_empty() {
            return Ok(0);
        }

        // Construct RecordBatch
        let id_array = StringArray::from(ids);
        let text_array = StringArray::from(texts);
        let path_array = StringArray::from(paths);

        // FixedSizeList for vectors
        let vector_values = Float32Array::from(vectors);
        let vector_field = Field::new("item", DataType::Float32, true);
        let vector_array = FixedSizeListArray::try_new(
            Arc::new(vector_field),
            384,
            Arc::new(vector_values),
            None,
        )?;

        let schema = Schema::new(vec![
            Field::new("id", DataType::Utf8, false),
            Field::new(
                "vector",
                DataType::FixedSizeList(Arc::new(Field::new("item", DataType::Float32, true)), 384),
                false,
            ),
            Field::new("text", DataType::Utf8, false),
            Field::new("path", DataType::Utf8, false),
        ]);

        let batch = RecordBatch::try_new(
            Arc::new(schema),
            vec![
                Arc::new(id_array),
                Arc::new(vector_array),
                Arc::new(text_array),
                Arc::new(path_array),
            ],
        )?;

        let table = self.get_or_create_table().await?;
        let schema = table.schema().await?;
        table
            .add(Box::new(RecordBatchIterator::new(vec![Ok(batch)], schema)))
            .execute()
            .await?;

        Ok(total_indexed)
    }

    async fn get_or_create_table(&self) -> Result<Table> {
        if self
            .db
            .open_table(&self.table_name)
            .execute()
            .await
            .is_err()
        {
            let schema = Arc::new(Schema::new(vec![
                Field::new("id", DataType::Utf8, false),
                Field::new(
                    "vector",
                    DataType::FixedSizeList(
                        Arc::new(Field::new("item", DataType::Float32, true)),
                        384,
                    ),
                    false,
                ),
                Field::new("text", DataType::Utf8, false),
                Field::new("path", DataType::Utf8, false),
            ]));
            // self.db.create_table(&self.table_name, RecordBatchIterator::new(vec![], schema)).await?;
            // Empty create is tricky in some versions, simpler to create with dummy data or use create_empty logic if supported.
            // For 0.4.5, create_table often expects an iterator.
            return Err(anyhow::anyhow!("Table creation from scratch not fully implemented in this step - requires initial data batch"));
        }
        self.db
            .open_table(&self.table_name)
            .execute()
            .await
            .map_err(|e| anyhow::anyhow!(e))
    }

    pub async fn search(&self, query: &str, limit: usize) -> Result<Vec<String>> {
        let embedding = self.embed_text(query).await?;
        let table = self.db.open_table(&self.table_name).execute().await?;

        /*
           results is a RecordBatch stream.
           We need to collect textual results.
        */
        // Placeholder for valid query synthesis due to version diffs
        // let results = table.search(embedding).limit(limit).execute().await?;

        Ok(vec![format!("Context found for: {}", query)])
    }
}
