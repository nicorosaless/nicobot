use std::env;

#[derive(Clone)]
pub struct Config {
    pub port: u16,
    /// Hermes Agent sidecar port (for agent mode)
    pub hermes_port: u16,
    /// Optional bearer key for the local Hermes API server — API_SERVER_KEY
    pub hermes_agent_api_key: Option<String>,
    /// Direct LLM API key — HERMES_API_KEY (Fireworks, OpenAI, etc.)
    pub hermes_api_key: Option<String>,
    /// Direct LLM base URL — HERMES_API_URL
    pub hermes_api_url: String,
    /// Direct LLM model name — HERMES_MODEL
    pub hermes_model: String,
    /// Legacy fallback LLM API key
    pub llm_api_key: Option<String>,
    /// Legacy fallback LLM endpoint URL
    pub llm_api_url: String,
    /// Legacy fallback LLM model name
    pub llm_model: String,
    /// STT API key (future)
    pub stt_api_key: Option<String>,
    /// TTS API key (future)
    pub tts_api_key: Option<String>,
    /// SQLite database path
    pub db_path: String,
}

impl Config {
    pub fn from_env() -> Self {
        Self {
            port: env::var("PORT")
                .ok()
                .and_then(|p| p.parse().ok())
                .unwrap_or(10201),
            hermes_port: env::var("HERMES_PORT")
                .ok()
                .and_then(|p| p.parse().ok())
                .unwrap_or(8642),
            hermes_agent_api_key: env::var("API_SERVER_KEY").ok(),
            hermes_api_key: env::var("HERMES_API_KEY").ok(),
            hermes_api_url: env::var("HERMES_API_URL")
                .unwrap_or_else(|_| "https://api.fireworks.ai/inference/v1".to_string()),
            hermes_model: env::var("HERMES_MODEL")
                .unwrap_or_else(|_| "accounts/fireworks/routers/kimi-k2p5-turbo".to_string()),
            llm_api_key: env::var("LLM_API_KEY").ok(),
            llm_api_url: env::var("LLM_API_URL")
                .unwrap_or_else(|_| "https://api.openai.com/v1".to_string()),
            llm_model: env::var("LLM_MODEL").unwrap_or_else(|_| "gpt-4o-mini".to_string()),
            stt_api_key: env::var("STT_API_KEY").ok(),
            tts_api_key: env::var("TTS_API_KEY").ok(),
            db_path: env::var("DB_PATH").unwrap_or_else(|_| "/tmp/umi.db".to_string()),
        }
    }

    pub fn validate(&self) {
        tracing::info!(
            "Hermes Agent: http://127.0.0.1:{}/v1/chat/completions / hermes-agent",
            self.hermes_port
        );
        if self.hermes_api_key.is_some() {
            tracing::info!(
                "Direct LLM fallback: {} / {}",
                self.hermes_api_url,
                self.hermes_model
            );
        } else if self.llm_api_key.is_some() {
            tracing::info!("Fallback LLM: {}", self.llm_api_url);
        } else {
            tracing::info!("No direct LLM fallback key set — chat will use the local Hermes Agent");
        }
    }
}
