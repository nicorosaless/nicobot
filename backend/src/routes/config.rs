use axum::{extract::State, http::StatusCode, routing::get, Json, Router};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

use crate::config::{normalize_tool_keys, persist_hermes_config, Config};
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
    temperature: Option<f64>,
    top_p: Option<f64>,
    max_tokens: Option<u32>,
    history_length: Option<usize>,
    enabled_tools: Option<Vec<String>>,
}

#[derive(Serialize)]
struct HermesConfigGetResponse {
    api_key: String,
    api_url: String,
    model: String,
    system_prompt: String,
    reasoning_effort: String,
    max_turns: u32,
    temperature: f64,
    top_p: f64,
    max_tokens: Option<u32>,
    history_length: usize,
    enabled_tools: Vec<String>,
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
    let config = state.config.load_full();
    Json(ConfigResponse {
        llm_api_url: config.llm_api_url.clone(),
        llm_model: config.llm_model.clone(),
        has_llm_key: config.llm_api_key.is_some(),
        has_stt_key: config.stt_api_key.is_some(),
        has_tts_key: config.tts_api_key.is_some(),
    })
}

async fn get_hermes_config(State(state): State<AppState>) -> Json<HermesConfigGetResponse> {
    let config = state.config.load_full();
    Json(HermesConfigGetResponse {
        api_key: config.hermes_api_key.clone().unwrap_or_default(),
        api_url: config.hermes_api_url.clone(),
        model: config.hermes_model.clone(),
        system_prompt: config.system_prompt.clone(),
        reasoning_effort: config.reasoning_effort.clone(),
        max_turns: config.max_turns,
        temperature: config.temperature,
        top_p: config.top_p,
        max_tokens: config.max_tokens,
        history_length: config.history_length,
        enabled_tools: config.enabled_tools.clone(),
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

    let current_config = state.config.load_full();

    let reasoning = req
        .reasoning_effort
        .as_deref()
        .unwrap_or("medium")
        .trim()
        .to_string();
    let max_turns = req.max_turns.unwrap_or(current_config.max_turns);
    let system_prompt = req
        .system_prompt
        .as_deref()
        .filter(|s| !s.trim().is_empty())
        .map(str::trim)
        .unwrap_or(current_config.system_prompt.as_str());
    let temperature = req.temperature.unwrap_or(current_config.temperature);
    let top_p = req.top_p.unwrap_or(current_config.top_p);
    let max_tokens = req.max_tokens.filter(|value| *value > 0);
    let history_length = req
        .history_length
        .unwrap_or(current_config.history_length)
        .clamp(2, 100);
    let enabled_tools = req
        .enabled_tools
        .as_deref()
        .map(normalize_tool_keys)
        .unwrap_or_else(|| current_config.enabled_tools.clone());

    let mut new_config: Config = (*current_config).clone();
    new_config.hermes_api_key = if req.api_key.trim().is_empty() {
        None
    } else {
        Some(req.api_key.trim().to_string())
    };
    new_config.hermes_api_url = api_url.to_string();
    new_config.hermes_model = model.to_string();
    new_config.system_prompt = system_prompt.to_string();
    new_config.reasoning_effort = reasoning;
    new_config.max_turns = max_turns;
    new_config.temperature = temperature;
    new_config.top_p = top_p;
    new_config.max_tokens = max_tokens;
    new_config.history_length = history_length;
    new_config.enabled_tools = enabled_tools;

    persist_hermes_config(&new_config).await.map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse { error: e }),
        )
    })?;

    state.config.store(Arc::new(new_config));

    Ok(Json(HermesConfigResponse {
        status: "ok".to_string(),
        message: "Hermes config guardada y aplicada al backend. Reinicia Hermes para aplicar cambios de herramientas.".to_string(),
    }))
}

pub fn config_routes() -> Router<AppState> {
    Router::new().route("/v1/config", get(get_config)).route(
        "/v1/hermes/config",
        get(get_hermes_config).post(save_hermes_config),
    )
}
