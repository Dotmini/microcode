use anyhow::Result;
use candle_core::{DType, Device, Tensor};
use candle_nn::VarBuilder;
use candle_transformers::models::qwen2::{Config, Model as Qwen2};
use hf_hub::{api::sync::Api, Repo, RepoType};
use tokenizers::Tokenizer; // Import VarBuilder directly

#[derive(Debug)]
pub struct FastTierEngine {
    model: Qwen2,
    tokenizer: Tokenizer,
    device: Device,
}

impl FastTierEngine {
    pub fn new() -> Result<Self> {
        // Use Metal if available (macOS), else CPU
        let device = if candle_core::utils::cuda_is_available() {
            Device::new_cuda(0)?
        } else if candle_core::utils::metal_is_available() {
            Device::new_metal(0)?
        } else {
            Device::Cpu
        };

        println!("FastTierEngine loading on device: {:?}", device);

        let api = Api::new()?;
        let model_id = "Qwen/Qwen2.5-Coder-1.5B-Instruct"; // Small, fast model
        let repo = api.repo(Repo::new(model_id.to_string(), RepoType::Model));

        let config_filename = repo.get("config.json")?;
        let tokenizer_filename = repo.get("tokenizer.json")?;

        let config: Config = serde_json::from_str(&std::fs::read_to_string(config_filename)?)?;
        let tokenizer = Tokenizer::from_file(tokenizer_filename).map_err(anyhow::Error::msg)?;

        // Load weights (safetensors)
        let weights_filenames: Vec<_> = vec![repo.get("model.safetensors")?];

        let vb = unsafe {
            VarBuilder::from_mmaped_safetensors(&weights_filenames, DType::F32, &device)?
        };

        // Load model
        let model = candle_transformers::models::qwen2::Model::new(&config, vb)?;

        Ok(Self {
            model,
            tokenizer,
            device,
        })
    }

    pub fn complete(&mut self, context_before: &str) -> Result<String> {
        let prompt = context_before; // For FIM models, we might format this differently
        let tokens = self
            .tokenizer
            .encode(prompt, true)
            .map_err(anyhow::Error::msg)?;
        let mut tokens = tokens.get_ids().to_vec();

        let mut generated_text = String::new();
        let max_new_tokens = 64; // Keep it short for autocomplete

        for _ in 0..max_new_tokens {
            let input = Tensor::new(tokens.as_slice(), &self.device)?.unsqueeze(0)?;
            let logits = self.model.forward(&input, 0, None)?;
            let logits = logits.squeeze(0)?.to_dtype(DType::F32)?;
            let logits = logits.get(logits.dim(0)? - 1)?;

            // Greedy sampling
            let next_token = logits.argmax(0)?.to_scalar::<u32>()?;
            tokens.push(next_token);

            // Decode step (simplified)
            if let Ok(text) = self.tokenizer.decode(&[next_token], true) {
                generated_text.push_str(&text);
                // Stop on newline for now to keep it sane for single line completion
                if text.contains('\n') {
                    break;
                }
            }
        }

        Ok(generated_text)
    }
}
