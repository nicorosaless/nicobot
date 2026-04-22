use serde::Deserialize;
use std::{collections::HashMap, env, fs, path::PathBuf};

pub const HERMES_TOOL_KEYS: &[&str] = &[
    "web",
    "browser",
    "terminal",
    "file",
    "code_execution",
    "vision",
    "image_gen",
    "moa",
    "tts",
    "skills",
    "todo",
    "memory",
    "session_search",
    "clarify",
    "delegation",
    "cronjob",
    "messaging",
    "homeassistant",
];

const DEFAULT_OFF_TOOL_KEYS: &[&str] = &["moa", "homeassistant"];

#[derive(Default, Deserialize)]
struct HermesYamlConfig {
    model: Option<HermesYamlModel>,
    agent: Option<HermesYamlAgent>,
    generation: Option<HermesYamlGeneration>,
    platform_toolsets: Option<HashMap<String, Vec<String>>>,
}

#[derive(Default, Deserialize)]
struct HermesYamlModel {
    api_key: Option<String>,
    base_url: Option<String>,
    #[serde(rename = "default")]
    default_model: Option<String>,
}

#[derive(Default, Deserialize)]
struct HermesYamlAgent {
    system_prompt: Option<String>,
    reasoning_effort: Option<String>,
    max_turns: Option<u32>,
}

#[derive(Default, Deserialize)]
struct HermesYamlGeneration {
    temperature: Option<f64>,
    top_p: Option<f64>,
    max_tokens: Option<u32>,
    history_length: Option<usize>,
}

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
    /// System prompt injected into chat requests.
    pub system_prompt: String,
    /// Sampling temperature.
    pub temperature: f64,
    /// Nucleus sampling top-p.
    pub top_p: f64,
    /// Optional maximum response tokens.
    pub max_tokens: Option<u32>,
    /// Number of prior messages to include in context.
    pub history_length: usize,
    /// Hermes Agent reasoning effort persisted to ~/.hermes/config.yaml.
    pub reasoning_effort: String,
    /// Hermes Agent maximum tool loop turns persisted to ~/.hermes/config.yaml.
    pub max_turns: u32,
    /// Enabled Hermes toolsets for the api_server platform.
    pub enabled_tools: Vec<String>,
}

impl Config {
    pub fn from_env() -> Self {
        let mut config = Self {
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
            system_prompt: env::var("HERMES_SYSTEM_PROMPT")
                .ok()
                .filter(|s| !s.trim().is_empty())
                .unwrap_or_else(default_system_prompt),
            temperature: env::var("HERMES_TEMPERATURE")
                .ok()
                .and_then(|p| p.parse().ok())
                .unwrap_or(0.7),
            top_p: env::var("HERMES_TOP_P")
                .ok()
                .and_then(|p| p.parse().ok())
                .unwrap_or(1.0),
            max_tokens: env::var("HERMES_MAX_TOKENS")
                .ok()
                .and_then(|p| p.parse::<u32>().ok())
                .filter(|value| *value > 0),
            history_length: env::var("HERMES_HISTORY_LENGTH")
                .ok()
                .and_then(|p| p.parse().ok())
                .unwrap_or(20),
            reasoning_effort: env::var("HERMES_REASONING_EFFORT")
                .unwrap_or_else(|_| "medium".to_string()),
            max_turns: env::var("HERMES_MAX_TURNS")
                .ok()
                .and_then(|p| p.parse().ok())
                .unwrap_or(10),
            enabled_tools: default_enabled_tools(),
        };

        if let Some(file_config) = load_hermes_yaml_config() {
            config.apply_hermes_yaml(file_config);
        }

        config
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

    fn apply_hermes_yaml(&mut self, yaml: HermesYamlConfig) {
        if let Some(model) = yaml.model {
            if let Some(api_key) = model.api_key {
                self.hermes_api_key = if api_key.trim().is_empty() {
                    None
                } else {
                    Some(api_key)
                };
            }
            if let Some(base_url) = model.base_url.filter(|value| !value.trim().is_empty()) {
                self.hermes_api_url = base_url;
            }
            if let Some(model_name) = model.default_model.filter(|value| !value.trim().is_empty()) {
                self.hermes_model = model_name;
            }
        }

        if let Some(agent) = yaml.agent {
            if let Some(system_prompt) =
                agent.system_prompt.filter(|value| !value.trim().is_empty())
            {
                self.system_prompt = system_prompt;
            }
            if let Some(reasoning_effort) = agent
                .reasoning_effort
                .filter(|value| !value.trim().is_empty())
            {
                self.reasoning_effort = reasoning_effort;
            }
            if let Some(max_turns) = agent.max_turns {
                self.max_turns = max_turns;
            }
        }

        if let Some(generation) = yaml.generation {
            if let Some(temperature) = generation.temperature {
                self.temperature = temperature;
            }
            if let Some(top_p) = generation.top_p {
                self.top_p = top_p;
            }
            self.max_tokens = generation.max_tokens.filter(|value| *value > 0);
            if let Some(history_length) = generation.history_length {
                self.history_length = history_length;
            }
        }

        if let Some(platform_toolsets) = yaml.platform_toolsets {
            if let Some(api_server_tools) = platform_toolsets.get("api_server") {
                self.enabled_tools = normalize_tool_keys(api_server_tools);
            }
        }
    }
}

pub fn default_system_prompt() -> String {
    read_runtime_soul_file().unwrap_or_else(|| include_str!("../../SOUL.md").trim().to_string())
}

pub fn default_enabled_tools() -> Vec<String> {
    HERMES_TOOL_KEYS
        .iter()
        .filter(|tool| !DEFAULT_OFF_TOOL_KEYS.contains(tool))
        .map(|tool| (*tool).to_string())
        .collect()
}

pub fn normalize_tool_keys(tools: &[String]) -> Vec<String> {
    tools
        .iter()
        .filter(|tool| HERMES_TOOL_KEYS.contains(&tool.as_str()))
        .cloned()
        .collect()
}

fn load_hermes_yaml_config() -> Option<HermesYamlConfig> {
    let path = hermes_config_path()?;
    let raw = fs::read_to_string(path).ok()?;
    serde_yaml::from_str::<HermesYamlConfig>(&raw).ok()
}

pub fn hermes_config_path() -> Option<PathBuf> {
    env::var_os("HOME")
        .map(PathBuf::from)
        .map(|home| home.join(".hermes").join("config.yaml"))
}

fn read_runtime_soul_file() -> Option<String> {
    let mut candidates = Vec::new();

    if let Ok(cwd) = env::current_dir() {
        candidates.push(cwd.join("SOUL.md"));
    }

    if let Ok(exe) = env::current_exe() {
        let mut current = exe.as_path();
        while let Some(parent) = current.parent() {
            candidates.push(parent.join("SOUL.md"));
            current = parent;
        }
    }

    candidates.into_iter().find_map(|path| {
        fs::read_to_string(path)
            .ok()
            .map(|content| content.trim().to_string())
            .filter(|content| !content.is_empty())
    })
}

pub async fn persist_hermes_config(config: &Config) -> Result<(), String> {
    let config_path = hermes_config_path()
        .ok_or_else(|| "HOME is not set; cannot write Hermes config".to_string())?;

    if let Some(parent) = config_path.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .map_err(|e| format!("failed to create Hermes config directory: {}", e))?;
    }

    tokio::fs::write(&config_path, render_hermes_config(config))
        .await
        .map_err(|e| format!("failed to write Hermes config: {}", e))
}

pub fn render_hermes_config(config: &Config) -> String {
    let generation_section = format!(
        "generation:\n  temperature: {}\n  top_p: {}\n  max_tokens: {}\n  history_length: {}\n",
        config.temperature,
        config.top_p,
        config
            .max_tokens
            .map(|value| value.to_string())
            .unwrap_or_else(|| "null".to_string()),
        config.history_length
    );
    let toolsets_section = if config.enabled_tools.is_empty() {
        "platform_toolsets:\n  api_server: []\n".to_string()
    } else {
        format!(
            "platform_toolsets:\n  api_server:\n{}\n",
            yaml_list(&config.enabled_tools, 4)
        )
    };

    format!(
        "model:\n  provider: \"custom\"\n  api_key: {}\n  base_url: {}\n  default: {}\nagent:\n  reasoning_effort: {}\n  max_turns: {}\n  system_prompt: {}\n{generation_section}{toolsets_section}platforms:\n  api_server:\n    enabled: true\n    extra:\n      port: {}\n      host: \"127.0.0.1\"\n",
        yaml_quote(config.hermes_api_key.as_deref().unwrap_or_default()),
        yaml_quote(&config.hermes_api_url),
        yaml_quote(&config.hermes_model),
        yaml_quote(&config.reasoning_effort),
        config.max_turns,
        yaml_quote(&config.system_prompt),
        config.hermes_port,
    )
}

pub fn yaml_quote(value: &str) -> String {
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

fn yaml_list(values: &[String], spaces: usize) -> String {
    let indent = " ".repeat(spaces);
    values
        .iter()
        .map(|value| format!("{indent}- {}", yaml_quote(value)))
        .collect::<Vec<_>>()
        .join("\n")
}
