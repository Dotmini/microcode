use serde_json::json;
use crate::CoreError;

#[uniffi::export]
pub async fn fetch_ghost_text(
    endpoint: String,
    model: String,
    prefix: String,
    suffix: String,
) -> Result<String, CoreError> {
    // FIM tags optimized for Qwen Coder / DeepSeek Coder.
    let use_deepseek = model.to_lowercase().contains("deepseek");
    
    let prompt = if use_deepseek {
        format!("<｜fim begin｜>{}<｜fim hole｜>{}<｜fim end｜>", prefix, suffix)
    } else {
        format!("<|fim_prefix|>{}<|fim_suffix|>{}<|fim_middle|>", prefix, suffix)
    };

    let body = json!({
        "model": model,
        "prompt": prompt,
        "max_tokens": 60,
        "temperature": 0.1,
        "top_p": 0.9,
        "stop": ["\n\n", "<|endoftext|>", "<|file_separator|>", "```", "<｜end of sentence｜>"]
    });

    let client = reqwest::Client::new();
    
    // Convert /chat/completions endpoint to /completions if necessary
    let url = endpoint.replace("/chat/completions", "/completions");

    let response = client
        .post(&url)
        .json(&body)
        .send()
        .await
        .map_err(|e| CoreError::Io {
            msg: format!("Failed to send request: {}", e),
        })?;

    if !response.status().is_success() {
        return Err(CoreError::Io {
            msg: format!("Server returned error: {}", response.status()),
        });
    }

    let result: serde_json::Value = response.json().await.map_err(|e| CoreError::ParseError {
        msg: format!("Failed to parse JSON response: {}", e),
    })?;

    if let Some(choices) = result.get("choices").and_then(|c| c.as_array()) {
        if let Some(first_choice) = choices.first() {
            if let Some(text) = first_choice.get("text").and_then(|t| t.as_str()) {
                let mut completion = text.to_string();
                
                // Cleanup artifacts
                if completion.starts_with("<|fim_middle|>") {
                    completion = completion["<|fim_middle|>".len()..].to_string();
                }
                if completion.starts_with("<｜fim hole｜>") {
                    completion = completion["<｜fim hole｜>".len()..].to_string();
                }
                
                return Ok(completion);
            }
        }
    }

    Ok(String::new())
}
