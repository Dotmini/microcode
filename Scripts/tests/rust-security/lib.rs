#[path = "../../../backend/src/policy.rs"]
mod policy;
#[path = "../../../backend/src/local_auth.rs"]
mod local_auth;

#[cfg(test)]
mod tests {
    use axum::{Router, routing::get, body::Body, http::{Request, StatusCode}};
    use std::sync::{Arc, atomic::{AtomicUsize, Ordering}};
    use tower::ServiceExt;

    #[tokio::test]
    async fn unauthorized_requests_never_reach_executor() {
        let calls = Arc::new(AtomicUsize::new(0));
        let count = calls.clone();
        let token = "a".repeat(64);
        let router = Router::new().route("/execute", get(move || async move {
            count.fetch_add(1, Ordering::SeqCst);
            "executed"
        })).layer(axum::middleware::from_fn_with_state(Arc::new(token.clone()), super::local_auth::require_local_token));
        for uri in ["/execute", "/execute?microcode_token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"] {
            let response = router.clone().oneshot(Request::builder().uri(uri).body(Body::empty()).unwrap()).await.unwrap();
            assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
        }
        assert_eq!(calls.load(Ordering::SeqCst), 0);
        let response = router.oneshot(Request::builder().uri("/execute").header("x-microcode-token", token).body(Body::empty()).unwrap()).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(calls.load(Ordering::SeqCst), 1);
    }
}

#[path = "../../../backend/src/mcp/gateway.rs"]
mod gateway;
