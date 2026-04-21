use axum::{
    extract::State,
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

use crate::AppState;

#[derive(Serialize)]
struct ConfigResponse {
    llm_api_url: String,
    llm_model: String,
    has_llm_key: bool,
    has_stt_key: bool,
    has_tts_key: bool,
}

#[derive(Deserialize)]
struct HermesConfigRequest {
    api_key: String,
    api_url: String,
    model: String,
    system_prompt: Option<String>,
    reasoning_effort: Option<String>,
    max_turns: Option<u32>,
}

#[derive(Serialize)]
struct HermesConfigResponse {
    status: String,
    message: String,
}

#[derive(Serialize)]
struct ErrorResponse {
    error: String,
}

async fn get_config(State(state): State<AppState>) -> Json<ConfigResponse> {
    Json(ConfigResponse {
        llm_api_url: state.config.llm_api_url.clone(),
        llm_model: state.config.llm_model.clone(),
        has_llm_key: state.config.llm_api_key.is_some(),
        has_stt_key: state.config.stt_api_key.is_some(),
        has_tts_key: state.config.tts_api_key.is_some(),
    })
}

async fn save_hermes_config(
    State(state): State<AppState>,
    Json(req): Json<HermesConfigRequest>,
) -> Result<Json<HermesConfigResponse>, (StatusCode, Json<ErrorResponse>)> {
    let api_url = req.api_url.trim();
    let model = req.model.trim();

    if api_url.is_empty() || model.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                error: "api_url and model are required".to_string(),
            }),
        ));
    }

    let config_path = hermes_config_path().ok_or_else(|| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                error: "HOME is not set; cannot write Hermes config".to_string(),
            }),
        )
    })?;

    if let Some(parent) = config_path.parent() {
        tokio::fs::create_dir_all(parent).await.map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    error: format!("failed to create Hermes config directory: {}", e),
                }),
            )
        })?;
    }

    let reasoning = req
        .reasoning_effort
        .as_deref()
        .unwrap_or("medium")
        .trim()
        .to_string();
    let max_turns = req.max_turns.unwrap_or(10);

    let agent_section = match req
        .system_prompt
        .as_deref()
        .filter(|s| !s.trim().is_empty())
    {
        Some(sp) => format!(
            "agent:\n  reasoning_effort: {}\n  max_turns: {}\n  system_prompt: {}\n",
            yaml_quote(&reasoning),
            max_turns,
            yaml_quote(sp.trim())
        ),
        None => format!(
            "agent:\n  reasoning_effort: {}\n  max_turns: {}\n",
            yaml_quote(&reasoning),
            max_turns
        ),
    };

    let yaml = format!(
        "model:\n  provider: \"custom\"\n  api_key: {}\n  base_url: {}\n  default: {}\n{agent_section}platforms:\n  api_server:\n    enabled: true\n    extra:\n      port: {}\n      host: \"127.0.0.1\"\n",
        yaml_quote(req.api_key.trim()),
        yaml_quote(api_url),
        yaml_quote(model),
        state.config.hermes_port,
    );

    tokio::fs::write(&config_path, yaml).await.map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                error: format!("failed to write Hermes config: {}", e),
            }),
        )
    })?;

    Ok(Json(HermesConfigResponse {
        status: "ok".to_string(),
        message: "Hermes config saved. Reinicia run.sh para aplicar cambios.".to_string(),
    }))
}

fn hermes_config_path() -> Option<PathBuf> {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .map(|home| home.join(".hermes").join("config.yaml"))
}

fn yaml_quote(value: &str) -> String {
    let mut quoted = String::from("\"");
    for ch in value.chars() {
        match ch {
            '\\' => quoted.push_str("\\\\"),
            '"' => quoted.push_str("\\\""),
            '\n' => quoted.push_str("\\n"),
            '\r' => quoted.push_str("\\r"),
            '\t' => quoted.push_str("\\t"),
            _ => quoted.push(ch),
        }
    }
    quoted.push('"');
    quoted
}

pub fn config_routes() -> Router<AppState> {
    Router::new()
        .route("/v1/config", get(get_config))
        .route("/v1/hermes/config", post(save_hermes_config))
}
