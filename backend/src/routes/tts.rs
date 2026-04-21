/// TTS proxy — stub for future TTS integration.
use axum::{http::StatusCode, routing::post, Router};

use crate::AppState;

async fn synthesize() -> StatusCode {
    StatusCode::NOT_IMPLEMENTED
}

pub fn tts_routes() -> Router<AppState> {
    Router::new().route("/v1/tts/synthesize", post(synthesize))
}
