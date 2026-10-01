use axum::{
    extract::{Request, State},
    http::StatusCode,
    middleware::Next,
    response::{IntoResponse, Response},
};
use std::sync::Arc;

pub async fn require_local_token(
    State(expected): State<Arc<String>>,
    request: Request,
    next: Next,
) -> Response {
    let header = request
        .headers()
        .get("x-microcode-token")
        .and_then(|v| v.to_str().ok());
    // Browser WebSocket API cannot set headers. Only this terminal endpoint
    // accepts a query capability; HTTP and MCP never accept tokens in URLs.
    let query_token = if request.uri().path() == "/ws/terminal" {
        request.uri().query().and_then(|q| {
            q.split('&')
                .find_map(|item| item.strip_prefix("microcode_token="))
        })
    } else {
        None
    };
    if !valid_token(header.or(query_token), &expected) {
        return StatusCode::UNAUTHORIZED.into_response();
    }
    next.run(request).await
}

fn valid_token(provided: Option<&str>, expected: &str) -> bool {
    let Some(provided) = provided else {
        return false;
    };
    if expected.len() < 32 || provided.len() != expected.len() {
        return false;
    }
    provided
        .bytes()
        .zip(expected.bytes())
        .fold(0u8, |diff, (a, b)| diff | (a ^ b))
        == 0
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_absent_short_and_incorrect_capabilities() {
        let token = "x".repeat(64);
        assert!(!valid_token(None, &token));
        assert!(!valid_token(Some(""), ""));
        assert!(!valid_token(Some(&"y".repeat(64)), &token));
        assert!(valid_token(Some(&token), &token));
    }
}
