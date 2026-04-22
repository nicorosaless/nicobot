// Health check routes

use axum::{extract::State, routing::get, Json, Router};
use serde::Serialize;

use crate::AppState;

#[derive(Serialize)]
pub struct HealthResponse {
    pub status: String,
    pub service: String,
    pub version: String,
}

#[derive(Serialize)]
pub struct HermesHealthResponse {
    pub status: String,
    pub hermes: bool,
}

/// Health check endpoint for Kubernetes probes
async fn health_check() -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "healthy".to_string(),
        service: "umi-backend".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
    })
}

async fn hermes_health(State(state): State<AppState>) -> Json<HermesHealthResponse> {
    let config = state.config.load_full();
    let url = format!("http://127.0.0.1:{}/health", config.hermes_port);
    let healthy = match reqwest::Client::new().get(url).send().await {
        Ok(resp) => resp.status().is_success(),
        Err(e) => {
            tracing::debug!("Hermes Agent health check failed: {}", e);
            false
        }
    };

    Json(HermesHealthResponse {
        status: if healthy { "healthy" } else { "unavailable" }.to_string(),
        hermes: healthy,
    })
}

pub fn health_routes() -> Router<AppState> {
    Router::new()
        .route("/health", get(health_check))
        .route("/v1/hermes/health", get(hermes_health))
        .route("/", get(health_check))
}
