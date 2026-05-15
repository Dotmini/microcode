use crate::error::Result;
use crate::models::AIRefactorReportRequest;
use genpdf::{elements, fonts, Element};
use std::io::Cursor;

pub async fn generate_pdf_report(req: AIRefactorReportRequest) -> Result<Vec<u8>> {
    let font_family = fonts::from_files("./assets/fonts", "Roboto", None).map_err(|e| {
        crate::error::AppError::InternalError(format!("Failed to load fonts: {}", e))
    })?;

    let mut doc = genpdf::Document::new(font_family);
    doc.set_title("AI Refactor Pro - Migration Report");

    let mut decorator = genpdf::SimplePageDecorator::new();
    decorator.set_margins(10);
    doc.set_page_decorator(decorator);

    // Header
    doc.push(
        elements::Text::new("AI REFACTOR PRO - MIGRATION REPORT")
            .styled(genpdf::style::Effect::Bold)
            .styled(genpdf::style::Color::Rgb(100, 0, 200)),
    );
    doc.push(elements::Break::new(1.0));

    // Summary Section
    doc.push(elements::Text::new("SUMMARY").styled(genpdf::style::Effect::Bold));
    doc.push(elements::Text::new(format!(
        "Source Language: {}",
        req.source_language
    )));
    doc.push(elements::Text::new(format!(
        "Target Language: {}",
        req.target_language
    )));
    doc.push(elements::Break::new(1.0));

    // Changes Section
    doc.push(elements::Text::new("CHANGES MADE").styled(genpdf::style::Effect::Bold));
    for change in req.changes {
        doc.push(elements::Text::new(format!("• {}", change)));
    }
    doc.push(elements::Break::new(1.0));

    // Recommendations Section
    doc.push(elements::Text::new("RECOMMENDATIONS").styled(genpdf::style::Effect::Bold));
    for rec in req.recommendations {
        doc.push(elements::Text::new(format!("💡 {}", rec)));
    }
    doc.push(elements::Break::new(1.0));

    // Code snippets (simplified for now)
    doc.push(elements::Text::new("REFACTORED CODE").styled(genpdf::style::Effect::Bold));
    doc.push(elements::Text::new(&req.refactored_code));

    let mut buf = Vec::new();
    doc.render(&mut buf).map_err(|e| {
        crate::error::AppError::InternalError(format!("Failed to render PDF: {}", e))
    })?;

    Ok(buf)
}
pub async fn generate_standup_summary(tasks: Vec<crate::tasks::Task>) -> Result<String> {
    let mut summary = String::from("# Daily Standup Summary\n\n");

    summary.push_str("## Completed Yesterday\n");
    let done_tasks: Vec<_> = tasks.iter().filter(|t| t.status == "done").collect();
    if done_tasks.is_empty() {
        summary.push_str("- No tasks completed.\n");
    } else {
        for task in done_tasks {
            summary.push_str(&format!("- **{}**: {}\n", task.title, task.description));
        }
    }

    summary.push_str("\n## In Progress Today\n");
    let in_progress: Vec<_> = tasks.iter().filter(|t| t.status == "in_progress").collect();
    if in_progress.is_empty() {
        summary.push_str("- No tasks in progress.\n");
    } else {
        for task in in_progress {
            summary.push_str(&format!(
                "- **{}** (Branch: {})\n",
                task.title,
                task.branch_name.as_deref().unwrap_or("none")
            ));
        }
    }

    summary.push_str("\n## Blockers\n- None reported.\n");

    Ok(summary)
}
