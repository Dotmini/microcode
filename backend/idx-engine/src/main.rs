mod bridge;
mod core;
mod services;

#[tokio::main]
async fn main() {
    println!("Starting IDX Engine...");

    // Initialize Core State
    let _doc = core::buffer::Document::new("untitled".to_string());

    println!("IDX Engine Ready.");
}
