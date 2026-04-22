use crate::config::Config;
use futures::{Stream, StreamExt};
use reqwest::StatusCode;
use serde::{Deserialize, Serialize};
use std::pin::Pin;

#[derive(Serialize)]
struct ChatRequest {
    model: String,
    messages: Vec<ChatMsg>,
    #[serde(skip_serializing_if = "Option::is_none")]
    stream: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    temperature: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    top_p: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    max_tokens: Option<u32>,
}

#[derive(Clone, Serialize, Deserialize)]
struct ChatMsg {
    role: String,
    content: String,
}

#[derive(Deserialize)]
struct ChatResponse {
    choices: Option<Vec<Choice>>,
    error: Option<serde_json::Value>,
}

#[derive(Deserialize)]
struct Choice {
    message: ChatMsg,
}

struct ChatEndpoint {
    service: &'static str,
    base_url: String,
    model: String,
    api_key: Option<String>,
}

#[derive(Deserialize)]
struct StreamChunk {
    choices: Vec<StreamChoice>,
}

#[derive(Deserialize)]
struct StreamChoice {
    delta: StreamDelta,
}

#[derive(Deserialize)]
struct StreamDelta {
    content: Option<String>,
}

#[derive(Clone, Debug)]
pub enum StreamItem {
    Token(String),
    ToolProgress {
        tool: String,
        emoji: String,
        label: String,
    },
}

#[derive(Debug, PartialEq)]
enum ChatCompletionSseItem {
    Token(String),
    ToolProgress {
        tool: String,
        emoji: String,
        label: String,
    },
    Done,
}

#[derive(Deserialize)]
struct ToolProgressPayload {
    tool: String,
    emoji: String,
    label: String,
}

#[derive(Default)]
struct ChatCompletionSseParser {
    buffer: Vec<u8>,
}

enum ChatGatewayError {
    Transport(reqwest::Error),
    InvalidResponse {
        status: StatusCode,
        body: String,
        source: reqwest::Error,
    },
    Json {
        status: StatusCode,
        body: String,
        source: serde_json::Error,
    },
    Http {
        status: StatusCode,
        body: String,
    },
    Api(serde_json::Value),
    NoContent,
    NoChoices,
}

pub async fn generate_response(
    prompt: &str,
    history: &[(String, String)],
    config: &Config,
) -> String {
    let messages = build_chat_messages(prompt, history, &config.system_prompt);
    let endpoints = chat_endpoints(config);
    let client = reqwest::Client::new();
    let mut last_error = None;

    for endpoint in &endpoints {
        let url = format!(
            "{}/chat/completions",
            endpoint.base_url.trim_end_matches('/')
        );
        let body = ChatRequest {
            model: endpoint.model.clone(),
            messages: messages.clone(),
            stream: None,
            temperature: Some(config.temperature),
            top_p: Some(config.top_p),
            max_tokens: config.max_tokens,
        };

        match send_chat_request(&client, &url, endpoint.api_key.as_deref(), &body).await {
            Ok(content) => return content,
            Err(e) => {
                tracing::error!("{} request failed: {}", endpoint.service, e.log_message());
                last_error = Some((endpoint.service, e));
            }
        }
    }

    if should_use_stub_fallback(&endpoints, last_error.as_ref().map(|(_, e)| e)) {
        return stub_response(prompt);
    }

    last_error
        .map(|(service, err)| err.user_message(service))
        .unwrap_or_else(|| stub_response(prompt))
}

async fn send_chat_request(
    client: &reqwest::Client,
    url: &str,
    api_key: Option<&str>,
    body: &ChatRequest,
) -> Result<String, ChatGatewayError> {
    let mut request = client.post(url).json(body);

    if let Some(api_key) = api_key {
        request = request.bearer_auth(api_key);
    }

    let response = request.send().await.map_err(ChatGatewayError::Transport)?;
    let status = response.status();
    let body_text = response
        .text()
        .await
        .map_err(|source| ChatGatewayError::InvalidResponse {
            status,
            body: String::new(),
            source,
        })?;

    if !status.is_success() {
        return Err(ChatGatewayError::Http {
            status,
            body: body_text,
        });
    }

    let data = serde_json::from_str::<ChatResponse>(&body_text).map_err(|source| {
        ChatGatewayError::Json {
            status,
            body: body_text.clone(),
            source,
        }
    })?;

    if let Some(err) = data.error {
        Err(ChatGatewayError::Api(err))
    } else if let Some(choices) = data.choices {
        choices
            .first()
            .map(|c| c.message.content.clone())
            .ok_or(ChatGatewayError::NoContent)
    } else {
        Err(ChatGatewayError::NoChoices)
    }
}

impl ChatGatewayError {
    fn log_message(&self) -> String {
        match self {
            Self::Transport(e) => format!("request failed: {}", e),
            Self::InvalidResponse {
                status,
                body,
                source,
            } => format!(
                "failed to read response body (status {}): {}{}",
                status,
                source,
                body_suffix(body)
            ),
            Self::Json {
                status,
                body,
                source,
            } => format!(
                "failed to parse response JSON (status {}): {}{}",
                status,
                source,
                body_suffix(body)
            ),
            Self::Http { status, body } => format!("HTTP {}{}", status, body_suffix(body)),
            Self::Api(err) => format!("API error: {:?}", err),
            Self::NoContent => "response contained no content".to_string(),
            Self::NoChoices => "response contained no choices".to_string(),
        }
    }

    fn user_message(&self, service: &str) -> String {
        match self {
            Self::Transport(e) => format!("No se pudo conectar al {}: {}", service, e),
            Self::InvalidResponse { status, body, .. } | Self::Json { status, body, .. } => {
                format!(
                    "Error al parsear respuesta del {} (status {}){}",
                    service,
                    status,
                    body_suffix(body)
                )
            }
            Self::Http { status, body } => {
                format!(
                    "{} respondió con HTTP {}{}",
                    service,
                    status,
                    body_suffix(body)
                )
            }
            Self::Api(err) => format!("Error del {}: {}", service, err),
            Self::NoContent => format!("El {} respondió sin contenido.", service),
            Self::NoChoices => format!("El {} respondió sin choices.", service),
        }
    }
}

fn body_suffix(body: &str) -> String {
    let trimmed = body.trim();
    if trimmed.is_empty() {
        String::new()
    } else {
        format!(" body: {}", trimmed)
    }
}

fn chat_endpoints(config: &Config) -> Vec<ChatEndpoint> {
    let mut endpoints = vec![ChatEndpoint {
        service: "Hermes Agent",
        base_url: format!("http://127.0.0.1:{}/v1", config.hermes_port),
        model: "hermes-agent".to_string(),
        api_key: config.hermes_agent_api_key.clone(),
    }];

    if let Some(api_key) = config
        .hermes_api_key
        .as_deref()
        .filter(|k| !k.trim().is_empty())
    {
        endpoints.push(ChatEndpoint {
            service: "Direct LLM",
            base_url: config.hermes_api_url.clone(),
            model: config.hermes_model.clone(),
            api_key: Some(api_key.to_string()),
        });
    }

    if let Some(api_key) = config
        .llm_api_key
        .as_deref()
        .filter(|k| !k.trim().is_empty())
    {
        endpoints.push(ChatEndpoint {
            service: "Fallback LLM",
            base_url: config.llm_api_url.clone(),
            model: config.llm_model.clone(),
            api_key: Some(api_key.to_string()),
        });
    }

    endpoints
}

fn should_use_stub_fallback(
    endpoints: &[ChatEndpoint],
    last_error: Option<&ChatGatewayError>,
) -> bool {
    endpoints.len() == 1 && matches!(last_error, Some(ChatGatewayError::Transport(_)) | None)
}

fn build_chat_messages(
    prompt: &str,
    history: &[(String, String)],
    system_prompt: &str,
) -> Vec<ChatMsg> {
    let mut messages = vec![ChatMsg {
        role: "system".to_string(),
        content: system_prompt.to_string(),
    }];
    for (role, content) in history {
        messages.push(ChatMsg {
            role: role.clone(),
            content: content.clone(),
        });
    }
    messages.push(ChatMsg {
        role: "user".to_string(),
        content: prompt.to_string(),
    });
    messages
}

pub async fn generate_response_stream(
    prompt: &str,
    history: &[(String, String)],
    config: &Config,
) -> Pin<Box<dyn Stream<Item = StreamItem> + Send>> {
    let messages = build_chat_messages(prompt, history, &config.system_prompt);
    let endpoints = chat_endpoints(config);
    let client = reqwest::Client::new();
    let mut last_error = None;

    for endpoint in &endpoints {
        let url = format!(
            "{}/chat/completions",
            endpoint.base_url.trim_end_matches('/')
        );
        let body = ChatRequest {
            model: endpoint.model.clone(),
            messages: messages.clone(),
            stream: Some(true),
            temperature: Some(config.temperature),
            top_p: Some(config.top_p),
            max_tokens: config.max_tokens,
        };

        match open_chat_stream(&client, &url, endpoint.api_key.as_deref(), &body).await {
            Ok(stream) => return stream,
            Err(e) => {
                tracing::error!(
                    "{} streaming request failed: {}",
                    endpoint.service,
                    e.log_message()
                );
                last_error = Some((endpoint.service, e));
            }
        }
    }

    if should_use_stub_fallback(&endpoints, last_error.as_ref().map(|(_, e)| e)) {
        return stream_text_incrementally(stub_response(prompt));
    }

    let msg = last_error
        .map(|(service, err)| err.user_message(service))
        .unwrap_or_else(|| stub_response(prompt));
    Box::pin(async_stream::stream! { yield StreamItem::Token(msg); })
}

async fn open_chat_stream(
    client: &reqwest::Client,
    url: &str,
    api_key: Option<&str>,
    body: &ChatRequest,
) -> Result<Pin<Box<dyn Stream<Item = StreamItem> + Send>>, ChatGatewayError> {
    let mut request = client.post(url).json(body);

    if let Some(api_key) = api_key {
        request = request.bearer_auth(api_key);
    }

    let response = request.send().await.map_err(ChatGatewayError::Transport)?;
    let status = response.status();

    if !status.is_success() {
        let body = response.text().await.unwrap_or_default();
        return Err(ChatGatewayError::Http { status, body });
    }

    let mut byte_stream = response.bytes_stream();
    Ok(Box::pin(async_stream::stream! {
        let mut parser = ChatCompletionSseParser::default();
        while let Some(chunk_result) = byte_stream.next().await {
            let bytes = match chunk_result {
                Ok(b) => b,
                Err(e) => {
                    tracing::error!("SSE stream read failed: {}", e);
                    break;
                }
            };

            for parsed in parser.push_bytes(&bytes) {
                match parsed {
                    Ok(ChatCompletionSseItem::Token(content)) => yield StreamItem::Token(content),
                    Ok(ChatCompletionSseItem::ToolProgress { tool, emoji, label }) => {
                        yield StreamItem::ToolProgress { tool, emoji, label };
                    }
                    Ok(ChatCompletionSseItem::Done) => return,
                    Err(e) => tracing::warn!("Ignoring malformed chat completion SSE event: {}", e),
                }
            }
        }
    }))
}

impl ChatCompletionSseParser {
    fn push_bytes(&mut self, bytes: &[u8]) -> Vec<Result<ChatCompletionSseItem, String>> {
        self.buffer.extend_from_slice(bytes);
        let mut items = Vec::new();

        while let Some((boundary, delimiter_len)) = find_sse_boundary(&self.buffer) {
            let raw_event = self.buffer[..boundary].to_vec();
            self.buffer.drain(..boundary + delimiter_len);

            if raw_event.iter().all(|b| b.is_ascii_whitespace()) {
                continue;
            }

            items.extend(parse_chat_completion_sse_event(&raw_event));
        }

        items
    }
}

fn find_sse_boundary(buffer: &[u8]) -> Option<(usize, usize)> {
    let lf = buffer.windows(2).position(|window| window == b"\n\n");
    let crlf = buffer.windows(4).position(|window| window == b"\r\n\r\n");

    match (lf, crlf) {
        (Some(lf_pos), Some(crlf_pos)) if lf_pos < crlf_pos => Some((lf_pos, 2)),
        (Some(_), Some(crlf_pos)) => Some((crlf_pos, 4)),
        (Some(lf_pos), None) => Some((lf_pos, 2)),
        (None, Some(crlf_pos)) => Some((crlf_pos, 4)),
        (None, None) => None,
    }
}

fn parse_chat_completion_sse_event(raw_event: &[u8]) -> Vec<Result<ChatCompletionSseItem, String>> {
    let text = String::from_utf8_lossy(raw_event);
    let mut event_name = None;
    let mut data = String::new();

    for line in text.lines() {
        let line = line.trim_end_matches('\r');
        if line.is_empty() || line.starts_with(':') {
            continue;
        }

        if let Some(value) = line.strip_prefix("event:") {
            event_name = Some(value.trim_start().to_string());
        } else if let Some(value) = line.strip_prefix("data:") {
            if !data.is_empty() {
                data.push('\n');
            }
            data.push_str(value.trim_start());
        }
    }

    if matches!(event_name.as_deref(), Some("hermes.tool.progress")) {
        if data.is_empty() {
            return Vec::new();
        }
        return match serde_json::from_str::<ToolProgressPayload>(&data) {
            Ok(payload) => vec![Ok(ChatCompletionSseItem::ToolProgress {
                tool: payload.tool,
                emoji: payload.emoji,
                label: payload.label,
            })],
            Err(e) => vec![Err(format!("{} while parsing {}", e, data))],
        };
    }

    if data.is_empty() {
        return Vec::new();
    }

    if data.trim() == "[DONE]" {
        return vec![Ok(ChatCompletionSseItem::Done)];
    }

    match serde_json::from_str::<StreamChunk>(&data) {
        Ok(chunk) => chunk
            .choices
            .into_iter()
            .filter_map(|choice| choice.delta.content)
            .filter(|content| !content.is_empty())
            .map(ChatCompletionSseItem::Token)
            .map(Ok)
            .collect(),
        Err(e) => vec![Err(format!("{} while parsing {}", e, data))],
    }
}

fn stream_text_incrementally(text: String) -> Pin<Box<dyn Stream<Item = StreamItem> + Send>> {
    let chunks: Vec<String> = text.split_inclusive(' ').map(str::to_string).collect();

    Box::pin(async_stream::stream! {
        for chunk in chunks {
            if !chunk.is_empty() {
                yield StreamItem::Token(chunk);
            }
        }
    })
}

fn stub_response(prompt: &str) -> String {
    let lower = prompt.to_lowercase();

    if lower.contains("hola") || lower.contains("hello") || lower.contains("hi") {
        return "¡Hola! Soy Umi. Arranca Hermes Agent con run.sh para obtener respuestas reales."
            .to_string();
    }

    format!(
        "Recibí: \"{}\". Arranca Hermes Agent con run.sh para obtener respuestas reales.",
        prompt
    )
}

pub fn greeting() -> String {
    "¡Hola! Soy Umi. ¿En qué puedo ayudarte?".to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse_all(chunks: &[&[u8]]) -> Vec<Result<ChatCompletionSseItem, String>> {
        let mut parser = ChatCompletionSseParser::default();
        let mut items = Vec::new();
        for chunk in chunks {
            items.extend(parser.push_bytes(chunk));
        }
        items
    }

    #[test]
    fn parses_normal_chat_completion_chunk() {
        let items = parse_all(&[
            br#"data: {"choices":[{"delta":{"content":"Hola"}}]}"#,
            b"\n\n",
        ]);

        assert_eq!(
            items,
            vec![Ok(ChatCompletionSseItem::Token("Hola".to_string()))]
        );
    }

    #[test]
    fn parses_done_marker() {
        let items = parse_all(&[b"data: [DONE]\n\n"]);

        assert_eq!(items, vec![Ok(ChatCompletionSseItem::Done)]);
    }

    #[test]
    fn parses_hermes_tool_progress_events() {
        let items = parse_all(&[
            b"event: hermes.tool.progress\ndata: {\"tool\":\"terminal\",\"emoji\":\"\xF0\x9F\x92\xBB\",\"label\":\"ls\"}\n\n",
        ]);

        assert_eq!(
            items,
            vec![Ok(ChatCompletionSseItem::ToolProgress {
                tool: "terminal".to_string(),
                emoji: "💻".to_string(),
                label: "ls".to_string()
            })]
        );
    }

    #[test]
    fn http_error_json_keeps_body_visible() {
        let err = ChatGatewayError::Http {
            status: StatusCode::BAD_REQUEST,
            body: r#"{"error":{"message":"bad request"}}"#.to_string(),
        };

        assert!(err.log_message().contains("HTTP 400"));
        assert!(err.log_message().contains("bad request"));
        assert!(err.user_message("Hermes Agent").contains("bad request"));
    }

    #[test]
    fn parses_tokens_fragmented_across_byte_chunks() {
        let items = parse_all(&[
            b"data: {\"choices\":[{\"delta\":{\"content\":\"He",
            b"llo\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"!\"}}]}\n\n",
        ]);

        assert_eq!(
            items,
            vec![
                Ok(ChatCompletionSseItem::Token("Hello".to_string())),
                Ok(ChatCompletionSseItem::Token("!".to_string()))
            ]
        );
    }
}
