use crate::ai;
use crate::error::Result;
use crate::models::{AIConfig, AIRefactorUltraRequest, AIRefactorUltraResponse, FileContent};
use std::path::Path;

pub async fn refactor_folder(
    req: AIRefactorUltraRequest,
    config: &AIConfig,
) -> Result<AIRefactorUltraResponse> {
    let mut refactored_files = Vec::new();
    let mut report_summary = String::from("Folder migration summary:\n");

    for file in req.files {
        let instructions = format!(
            "{}\n\nTarget Language: {}\nFile Path: {}",
            req.instructions,
            req.target_language.as_deref().unwrap_or("same as source"),
            file.path
        );

        let refactored_code = ai::refactor(&file.content, &instructions, config).await?;

        refactored_files.push(FileContent {
            path: file.path.clone(),
            content: refactored_code,
        });

        report_summary.push_str(&format!("- Processing {}\n", file.path));
    }

    Ok(AIRefactorUltraResponse {
        refactored_files,
        report_summary,
    })
}
