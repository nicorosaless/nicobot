use axum::{
    extract::State,
    http::StatusCode,
    response::Response,
    routing::post,
    Json, Router,
};
use serde::{Deserialize, Serialize};

use crate::AppState;

#[derive(Deserialize)]
struct SynthesizeRequest {
    text: String,
    voice_id: String,
    model_id: Option<String>,
    output_format: Option<String>,
    voice_settings: Option<VoiceSettings>,
}

#[derive(Clone, Deserialize, Serialize)]
struct VoiceSettings {
    stability: f64,
    similarity_boost: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    style: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    use_speaker_boost: Option<bool>,
}

#[derive(Serialize)]
struct ElevenLabsRequest {
    text: String,
    model_id: String,
    output_format: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    voice_settings: Option<VoiceSettings>,
}

#[derive(Serialize)]
struct ChatterboxRequest {
    text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    voice_id: Option<String>,
}

#[derive(Serialize)]
struct KokoroRequest {
    text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    voice: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    speed: Option<f64>,
}

async fn try_chatterbox(
    config: &crate::config::Config,
    req: &SynthesizeRequest,
) -> Option<Result<Response, StatusCode>> {
    let sidecar_url = config.chatterbox_tts_url.as_ref()?;

    let client = reqwest::Client::builder()
        .connect_timeout(std::time::Duration::from_secs(3))
        .timeout(std::time::Duration::from_secs(120))
        .build()
        .ok()?;

    let url = format!("{}/generate", sidecar_url.trim_end_matches('/'));

    let voice_id = if req.voice_id.is_empty() {
        config.chatterbox_default_voice_id.clone()
    } else {
        req.voice_id.clone()
    };

    let body = ChatterboxRequest {
        text: req.text.clone(),
        voice_id: Some(voice_id),
    };

    let resp = match client.post(&url).json(&body).send().await {
        Ok(r) => r,
        Err(e) => {
            tracing::warn!("Chatterbox sidecar unreachable: {}", e);
            return Some(Err(StatusCode::BAD_GATEWAY));
        }
    };

    if !resp.status().is_success() {
        let status = resp.status();
        let body_text = resp.text().await.unwrap_or_default();
        tracing::warn!(
            "Chatterbox sidecar returned {}: {}",
            status,
            body_text
        );
        return Some(Err(StatusCode::BAD_GATEWAY));
    }

    let audio_bytes = match resp.bytes().await {
        Ok(b) => b,
        Err(e) => {
            tracing::warn!("Failed to read Chatterbox audio bytes: {}", e);
            return Some(Err(StatusCode::BAD_GATEWAY));
        }
    };

    tracing::info!(
        "TTS served via Chatterbox ({} bytes)",
        audio_bytes.len()
    );

    Some(Ok(Response::builder()
        .status(StatusCode::OK)
        .header("content-type", "audio/wav")
        .body(axum::body::Body::from(audio_bytes))
        .unwrap()))
}

async fn try_kokoro(
    config: &crate::config::Config,
    req: &SynthesizeRequest,
) -> Option<Result<Response, StatusCode>> {
    let sidecar_url = config.kokoro_tts_url.as_ref()?;

    let client = reqwest::Client::builder()
        .connect_timeout(std::time::Duration::from_secs(3))
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .ok()?;

    let url = format!("{}/generate", sidecar_url.trim_end_matches('/'));

    let body = KokoroRequest {
        text: req.text.clone(),
        voice: None,
        speed: None,
    };

    let resp = match client.post(&url).json(&body).send().await {
        Ok(r) => r,
        Err(e) => {
            tracing::warn!("Kokoro sidecar unreachable: {}", e);
            return Some(Err(StatusCode::BAD_GATEWAY));
        }
    };

    if !resp.status().is_success() {
        let status = resp.status();
        let body_text = resp.text().await.unwrap_or_default();
        tracing::warn!(
            "Kokoro sidecar returned {}: {}",
            status,
            body_text
        );
        return Some(Err(StatusCode::BAD_GATEWAY));
    }

    let audio_bytes = match resp.bytes().await {
        Ok(b) => b,
        Err(e) => {
            tracing::warn!("Failed to read Kokoro audio bytes: {}", e);
            return Some(Err(StatusCode::BAD_GATEWAY));
        }
    };

    tracing::info!(
        "TTS served via Kokoro ({} bytes)",
        audio_bytes.len()
    );

    Some(Ok(Response::builder()
        .status(StatusCode::OK)
        .header("content-type", "audio/wav")
        .body(axum::body::Body::from(audio_bytes))
        .unwrap()))
}

async fn try_elevenlabs(
    config: &crate::config::Config,
    req: &SynthesizeRequest,
) -> Result<Response, StatusCode> {
    let api_key = config
        .tts_api_key
        .clone()
        .ok_or(StatusCode::NOT_IMPLEMENTED)?;

    let url = format!(
        "https://api.elevenlabs.io/v1/text-to-speech/{}/stream",
        req.voice_id
    );

    let body = ElevenLabsRequest {
        text: req.text.clone(),
        model_id: req.model_id.clone().unwrap_or_else(|| "eleven_multilingual_v2".to_string()),
        output_format: req.output_format.clone().unwrap_or_else(|| "mp3_44100_128".to_string()),
        voice_settings: req.voice_settings.clone(),
    };

    let client = reqwest::Client::new();
    let resp = client
        .post(&url)
        .header("xi-api-key", &api_key)
        .header("Content-Type", "application/json")
        .header("Accept", "audio/mpeg")
        .json(&body)
        .send()
        .await
        .map_err(|_| StatusCode::BAD_GATEWAY)?;

    if !resp.status().is_success() {
        tracing::warn!("ElevenLabs returned {}", resp.status());
        return Err(StatusCode::BAD_GATEWAY);
    }

    let audio_bytes = resp.bytes().await.map_err(|_| StatusCode::BAD_GATEWAY)?;

    tracing::info!("TTS served via ElevenLabs ({} bytes)", audio_bytes.len());

    Ok(Response::builder()
        .status(StatusCode::OK)
        .header("content-type", "audio/mpeg")
        .body(axum::body::Body::from(audio_bytes))
        .unwrap())
}

async fn synthesize(
    State(state): State<AppState>,
    Json(req): Json<SynthesizeRequest>,
) -> Result<Response, StatusCode> {
    let config = state.config.load_full();

    // 1) Try fast local Kokoro TTS first (~1-2s)
    if let Some(kokoro_result) = try_kokoro(&config, &req).await {
        match kokoro_result {
            Ok(response) => return Ok(response),
            Err(StatusCode::BAD_GATEWAY) => {
                tracing::info!("Kokoro failed; trying Chatterbox fallback");
            }
            Err(other) => return Err(other),
        }
    }

    // 2) Fallback to Chatterbox (voice clone quality, slower)
    if let Some(chatterbox_result) = try_chatterbox(&config, &req).await {
        match chatterbox_result {
            Ok(response) => return Ok(response),
            Err(StatusCode::BAD_GATEWAY) => {
                tracing::info!("Chatterbox failed; trying ElevenLabs fallback");
            }
            Err(other) => return Err(other),
        }
    }

    // 3) Fallback to ElevenLabs
    try_elevenlabs(&config, &req).await
}

pub fn tts_routes() -> Router<AppState> {
    Router::new().route("/v1/tts/synthesize", post(synthesize))
}
