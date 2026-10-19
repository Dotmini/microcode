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
    // 1. Defense-in-depth against DNS Rebinding: verify Host header is loopback if present
    if let Some(host) = request.headers().get("host").and_then(|v| v.to_str().ok()) {
        if !is_allowed_loopback_host(host) {
            return StatusCode::FORBIDDEN.into_response();
        }
    }

    // 2. Defense-in-depth against browser CSRF: reject external web Origins
    if let Some(origin) = request.headers().get("origin").and_then(|v| v.to_str().ok()) {
        if !is_allowed_origin(origin) {
            return StatusCode::FORBIDDEN.into_response();
        }
    }

    let header = request
        .headers()
        .get("x-microcode-token")
        .and_then(|v| v.to_str().ok());
    // Browser WebSocket API cannot set custom headers. Only WebSocket endpoints
    // accept a query capability; HTTP and MCP never accept tokens in URLs.
    let path = request.uri().path();
    let is_ws_endpoint = path == "/ws/terminal" || path.starts_with("/api/remote/ws/");
    let query_token = if is_ws_endpoint {
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

fn is_allowed_loopback_host(host: &str) -> bool {
    let h = host.trim().to_ascii_lowercase();
    let hostname = if let Some(rest) = h.strip_prefix('[') {
        rest.split(']').next().unwrap_or("")
    } else {
        h.split(':').next().unwrap_or("")
    };
    matches!(hostname, "127.0.0.1" | "localhost" | "::1" | "0.0.0.0")
}

fn is_allowed_origin(origin: &str) -> bool {
    let o = origin.trim().to_ascii_lowercase();
    if o == "null" || o.starts_with("file://") || o.starts_with("app://") {
        return true;
    }
    for prefix in ["http://", "https://", "ws://", "wss://"] {
        if let Some(rest) = o.strip_prefix(prefix) {
            let host_port = rest.split('/').next().unwrap_or("");
            return is_allowed_loopback_host(host_port);
        }
    }
    false
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
        assert!(is_allowed_loopback_host("127.0.0.1:3000"));
        assert!(is_allowed_loopback_host("localhost:3000"));
        assert!(!is_allowed_loopback_host("evil.example.com:3000"));
        assert!(is_allowed_origin("http://127.0.0.1:3000"));
        assert!(!is_allowed_origin("https://evil.example.com"));
    }
}
