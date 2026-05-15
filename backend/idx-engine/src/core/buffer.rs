use ropey::Rope;
use std::sync::{Arc, RwLock};

pub struct Document {
    pub uri: String,
    pub content: Arc<RwLock<Rope>>,
    pub version: u64,
}

impl Document {
    pub fn new(uri: String) -> Self {
        Self {
            uri,
            content: Arc::new(RwLock::new(Rope::new())),
            version: 0,
        }
    }

    pub fn new_with_text(uri: String, text: &str) -> Self {
        Self {
            uri,
            content: Arc::new(RwLock::new(Rope::from_str(text))),
            version: 0,
        }
    }

    pub fn apply_edit(&self, start: usize, end: usize, text: &str) {
        if let Ok(mut rope) = self.content.write() {
            // Safety: Ropey handles char boundary checks, but we should be careful with byte->char conversion in real impl
            // For MVP assuming start/end are valid char indices or byte indices depending on protocol
            let start_char = rope.byte_to_char(start);
            let end_char = rope.byte_to_char(end);

            if start_char <= rope.len_chars() && end_char <= rope.len_chars() {
                rope.remove(start_char..end_char);
                rope.insert(start_char, text);
            }
        }
    }

    pub fn get_text(&self) -> String {
        if let Ok(rope) = self.content.read() {
            return String::from(&rope);
        }
        String::new()
    }
}
