use crate::core::buffer::Document;
use std::collections::HashMap;
use std::sync::{Arc, RwLock};

pub struct AppState {
    pub documents: Arc<RwLock<HashMap<String, Document>>>,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            documents: Arc::new(RwLock::new(HashMap::new())),
        }
    }
}
