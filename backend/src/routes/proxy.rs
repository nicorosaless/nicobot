/// LLM proxy — forwards requests to the configured LLM endpoint.
/// The API key stays server-side; the desktop app never sees it.
use axum::{
    body::Bytes,
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    response::Response,
    routing::any,
    Router,
};

use crate::AppState;

async fn llm_proxy(
    State(state): State<AppState>,
    Path(path): Path<String>,
    headers: HeaderMap,
    body: Bytes,
) -> Result<Response, StatusCode> {
    let key = state
        .config
        .llm_api_key
        .as_deref()
        .ok_or(StatusCode::SERVICE_UNAVAILABLE)?;

    let url = format!(
        "{}/{}",
        state.config.llm_api_url.trim_end_matches('/'),
        path
    );

    let client = reqwest::Client::new();
    let mut req = client.post(&url).bearer_auth(key).body(body.to_vec());

    if let Some(ct) = headers.get("content-type") {
        if let Ok(ct_str) = ct.to_str() {
            req = req.header("content-type", ct_str);
        }
    }

    let resp = req.send().await.map_err(|_| StatusCode::BAD_GATEWAY)?;

    let status = resp.status();
    let resp_bytes = resp.bytes().await.map_err(|_| StatusCode::BAD_GATEWAY)?;

    Ok(Response::builder()
        .status(status.as_u16())
        .header("content-type", "application/json")
        .body(axum::body::Body::from(resp_bytes))
        .unwrap())
}

pub fn proxy_routes() -> Router<AppState> {
    Router::new().route("/v1/proxy/llm/*path", any(llm_proxy))
}
