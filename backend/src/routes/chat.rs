use axum::{
    extract::{
        ws::{Message, WebSocket},
        Path, State, WebSocketUpgrade,
    },
    http::StatusCode,
    response::{
        sse::{Event, KeepAlive, Sse},
        IntoResponse,
    },
    routing::{get, post},
    Json, Router,
};
use futures::{Stream, StreamExt};
use serde::{Deserialize, Serialize};
use std::{convert::Infallible, pin::Pin, sync::Arc};

use crate::config::persist_hermes_config;
use crate::hermes::StreamItem;
use crate::AppState;

const PROFILE_BLOCK_START: &str = "\n\n<!-- umi-persistent-profile:start -->\n";
const PROFILE_BLOCK_END: &str = "\n<!-- umi-persistent-profile:end -->";

fn clean_for_tts(s: &str) -> String {
    // Strip markdown syntax
    let mut out = s
        .replace("**", "")
        .replace("__", "")
        .replace("*", "")
        .replace("_", "")
        .replace("```", "")
        .replace("`", "");
    // Strip leading # heading markers
    while out.starts_with('#') {
        out = out.trim_start_matches('#').trim_start().to_string();
    }
    // Strip emoji (common Unicode blocks)
    out.chars()
        .filter(|&c| {
            !matches!(c,
                '\u{1F000}'..='\u{1FFFF}'
                | '\u{2600}'..='\u{27BF}'
                | '\u{2B00}'..='\u{2BFF}'
                | '\u{FE00}'..='\u{FE0F}'
                | '\u{E0000}'..='\u{E007F}'
            )
        })
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

#[derive(Deserialize)]
pub struct SendMessageRequest {
    pub session_id: Option<String>,
    pub text: String,
}

#[derive(Serialize)]
pub struct SendMessageResponse {
    pub session_id: String,
    pub message_id: String,
    pub response: String,
}

#[derive(Deserialize)]
pub struct CreateSessionRequest {
    pub title: Option<String>,
}

#[derive(Serialize)]
pub struct SessionResponse {
    pub session_id: String,
}

async fn send_message(
    State(state): State<AppState>,
    Json(req): Json<SendMessageRequest>,
) -> Result<Json<SendMessageResponse>, StatusCode> {
    let session_id = match req.session_id.filter(|s| !s.is_empty()) {
        Some(id) => id,
        None => state
            .db
            .create_session(None)
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?,
    };

    state
        .db
        .add_message(&session_id, "user", &req.text)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    if let Some(response_text) = maybe_persist_profile_update(&state, &req.text).await {
        let message_id = state
            .db
            .add_message(&session_id, "assistant", &response_text)
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        return Ok(Json(SendMessageResponse {
            session_id,
            message_id,
            response: response_text,
        }));
    }

    // Load recent history for context
    let all_msgs = state.db.get_messages(&session_id).unwrap_or_default();
    let history: Vec<(String, String)> = all_msgs
        .iter()
        .map(|m| (m.role.clone(), m.content.clone()))
        .collect();
    let config = state.config.load_full();

    // Limit to last 20, exclude the current prompt (hermes adds it)
    let context_limit = config.history_length.saturating_add(1);
    let start = if history.len() > context_limit {
        history.len() - context_limit
    } else {
        0
    };
    let context: Vec<(String, String)> = history[start..]
        .iter()
        .rev()
        .skip(1)
        .rev()
        .cloned()
        .collect();

    let response_text = crate::hermes::generate_response(&req.text, &context, &config).await;

    let message_id = state
        .db
        .add_message(&session_id, "assistant", &response_text)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(SendMessageResponse {
        session_id,
        message_id,
        response: response_text,
    }))
}

async fn create_session(
    State(state): State<AppState>,
    Json(req): Json<CreateSessionRequest>,
) -> Result<Json<SessionResponse>, StatusCode> {
    let session_id = state
        .db
        .create_session(req.title.as_deref())
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(SessionResponse { session_id }))
}

async fn list_sessions(
    State(state): State<AppState>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let sessions = state
        .db
        .list_sessions()
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(serde_json::json!({ "sessions": sessions })))
}

async fn get_messages(
    State(state): State<AppState>,
    Path(session_id): Path<String>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let messages = state
        .db
        .get_messages(&session_id)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(serde_json::json!({ "messages": messages })))
}

#[derive(Deserialize)]
struct WsChatRequest {
    text: String,
    session_id: Option<String>,
}

async fn ws_chat(ws: WebSocketUpgrade, State(state): State<AppState>) -> impl IntoResponse {
    ws.on_upgrade(|socket| handle_ws_chat(socket, state))
}

async fn handle_ws_chat(mut socket: WebSocket, state: AppState) {
    // 1. Receive the initial request message
    let raw = match socket.recv().await {
        Some(Ok(Message::Text(t))) => t,
        _ => return,
    };

    let req: WsChatRequest = match serde_json::from_str(&raw) {
        Ok(r) => r,
        Err(_) => {
            let _ = socket
                .send(Message::Text(
                    r#"{"t":"err","d":"invalid request"}"#.to_string(),
                ))
                .await;
            return;
        }
    };

    // 2. Get or create session
    let session_id = match req.session_id.filter(|s| !s.is_empty()) {
        Some(id) => id,
        None => match state.db.create_session(None) {
            Ok(id) => id,
            Err(_) => {
                let _ = socket
                    .send(Message::Text(
                        r#"{"t":"err","d":"failed to create session"}"#.to_string(),
                    ))
                    .await;
                return;
            }
        },
    };

    // 3. Save user message
    if state
        .db
        .add_message(&session_id, "user", &req.text)
        .is_err()
    {
        let _ = socket
            .send(Message::Text(r#"{"t":"err","d":"db error"}"#.to_string()))
            .await;
        return;
    }

    if let Some(response_text) = maybe_persist_profile_update(&state, &req.text).await {
        let tool_msg = serde_json::json!({
            "t": "tool",
            "tool": "config.write",
            "emoji": "💾",
            "label": "Ahora voy a guardar tu perfil persistente"
        })
        .to_string();
        if socket.send(Message::Text(tool_msg)).await.is_err() {
            return;
        }
        let tok_msg = serde_json::json!({"t": "tok", "d": response_text}).to_string();
        if socket.send(Message::Text(tok_msg)).await.is_err() {
            return;
        }
        let message_id = state
            .db
            .add_message(&session_id, "assistant", &response_text)
            .unwrap_or_else(|_| "unknown".to_string());
        let done_msg = serde_json::json!({
            "t": "done",
            "session_id": session_id,
            "message_id": message_id
        })
        .to_string();
        let _ = socket.send(Message::Text(done_msg)).await;
        return;
    }

    // 4. Load history for context (same logic as HTTP handler)
    let all_msgs = state.db.get_messages(&session_id).unwrap_or_default();
    let history: Vec<(String, String)> = all_msgs
        .iter()
        .map(|m| (m.role.clone(), m.content.clone()))
        .collect();
    let config = state.config.load_full();
    let context_limit = config.history_length.saturating_add(1);
    let start = if history.len() > context_limit {
        history.len() - context_limit
    } else {
        0
    };
    let context: Vec<(String, String)> = history[start..]
        .iter()
        .rev()
        .skip(1)
        .rev()
        .cloned()
        .collect();

    // 5. Stream tokens from LLM
    let mut token_stream =
        crate::hermes::generate_response_stream(&req.text, &context, &config).await;

    let mut full_response = String::new();
    let mut sentence_buf = String::new();

    while let Some(item) = token_stream.next().await {
        match item {
            StreamItem::Token(token) => {
                full_response.push_str(&token);
                sentence_buf.push_str(&token);

                // Send token event
                let tok_msg = serde_json::json!({"t": "tok", "d": token}).to_string();
                if socket.send(Message::Text(tok_msg)).await.is_err() {
                    return; // client disconnected
                }

                // Emit sentence events on sentence boundaries (for TTS)
                loop {
                    match sentence_buf.find(|c: char| matches!(c, '.' | '!' | '?' | '\n')) {
                        None => break,
                        Some(pos) => {
                            let sentence = sentence_buf[..=pos].trim().to_string();
                            sentence_buf = sentence_buf[pos + 1..].to_string();
                            let clean = clean_for_tts(&sentence);
                            if clean.len() > 1 {
                                let sent_msg =
                                    serde_json::json!({"t": "sent", "d": clean}).to_string();
                                let _ = socket.send(Message::Text(sent_msg)).await;
                            }
                        }
                    }
                }
            }
            StreamItem::ToolProgress { tool, emoji, label } => {
                let narrated_label = narrate_tool_progress(&tool, &label);
                let tool_msg = serde_json::json!({
                    "t": "tool",
                    "tool": tool,
                    "emoji": emoji,
                    "label": narrated_label
                })
                .to_string();
                if socket.send(Message::Text(tool_msg)).await.is_err() {
                    return;
                }
            }
        }
    }

    if full_response.trim().is_empty() {
        tracing::warn!("Hermes websocket stream ended without tokens; falling back to non-streaming chat completion");
        let fallback = crate::hermes::generate_response(&req.text, &context, &config).await;
        if !fallback.trim().is_empty() {
            full_response.push_str(&fallback);
            sentence_buf.push_str(&fallback);
            let tok_msg = serde_json::json!({"t": "tok", "d": fallback}).to_string();
            if socket.send(Message::Text(tok_msg)).await.is_err() {
                return;
            }
        }
    }

    if full_response.trim().is_empty() {
        full_response =
            "Hermes no devolvió texto para esta respuesta. Prueba de nuevo.".to_string();
        sentence_buf.push_str(&full_response);
        let tok_msg = serde_json::json!({"t": "tok", "d": full_response}).to_string();
        if socket.send(Message::Text(tok_msg)).await.is_err() {
            return;
        }
    }

    let final_sentence = sentence_buf.trim();
    if final_sentence.len() > 1 {
        let sent_msg = serde_json::json!({"t": "sent", "d": final_sentence}).to_string();
        let _ = socket.send(Message::Text(sent_msg)).await;
    }

    // 6. Persist full assistant response
    let message_id = state
        .db
        .add_message(&session_id, "assistant", &full_response)
        .unwrap_or_else(|_| "unknown".to_string());

    // 7. Signal completion
    let done_msg = serde_json::json!({
        "t": "done",
        "session_id": session_id,
        "message_id": message_id
    })
    .to_string();
    let _ = socket.send(Message::Text(done_msg)).await;
}

async fn stream_chat(
    State(state): State<AppState>,
    Json(req): Json<SendMessageRequest>,
) -> Result<Sse<Pin<Box<dyn Stream<Item = Result<Event, Infallible>> + Send>>>, StatusCode> {
    let session_id = match req.session_id.filter(|s| !s.is_empty()) {
        Some(id) => id,
        None => state
            .db
            .create_session(None)
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?,
    };

    state
        .db
        .add_message(&session_id, "user", &req.text)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    if let Some(response_text) = maybe_persist_profile_update(&state, &req.text).await {
        let db = state.db.clone();
        let sid = session_id.clone();
        let event_stream = async_stream::stream! {
            yield Ok(Event::default().event("tool").data(
                serde_json::json!({
                    "tool": "config.write",
                    "emoji": "💾",
                    "label": "Ahora voy a guardar tu perfil persistente"
                }).to_string(),
            ));

            yield Ok(Event::default().event("tok").data(response_text.clone()));

            let message_id = db
                .add_message(&sid, "assistant", &response_text)
                .unwrap_or_else(|_| "unknown".to_string());

            yield Ok(Event::default().event("done").data(
                serde_json::json!({"session_id": sid, "message_id": message_id}).to_string(),
            ));
        };

        return Ok(boxed_sse(event_stream));
    }

    let all_msgs = state.db.get_messages(&session_id).unwrap_or_default();
    let history: Vec<(String, String)> = all_msgs
        .iter()
        .map(|m| (m.role.clone(), m.content.clone()))
        .collect();
    let config = state.config.load_full();
    let context_limit = config.history_length.saturating_add(1);
    let start = if history.len() > context_limit {
        history.len() - context_limit
    } else {
        0
    };
    let context: Vec<(String, String)> = history[start..]
        .iter()
        .rev()
        .skip(1)
        .rev()
        .cloned()
        .collect();

    let prompt = req.text.clone();
    let db = state.db.clone();
    let sid = session_id.clone();

    let event_stream = async_stream::stream! {
        let mut token_stream =
            crate::hermes::generate_response_stream(&prompt, &context, &config).await;

        let mut full_response = String::new();
        let mut sentence_buf = String::new();

        while let Some(item) = token_stream.next().await {
            match item {
                StreamItem::Token(token) => {
                    full_response.push_str(&token);
                    sentence_buf.push_str(&token);

                    yield Ok(Event::default().event("tok").data(&token));

                    loop {
                        match sentence_buf.find(|c: char| matches!(c, '.' | '!' | '?' | '\n')) {
                            None => break,
                            Some(pos) => {
                                let sentence = sentence_buf[..=pos].trim().to_string();
                                sentence_buf = sentence_buf[pos + 1..].to_string();
                                let clean = clean_for_tts(&sentence);
                                if clean.len() > 1 {
                                    yield Ok(Event::default().event("sent").data(clean));
                                }
                            }
                        }
                    }
                }
                StreamItem::ToolProgress { tool, emoji, label } => {
                    let narrated_label = narrate_tool_progress(&tool, &label);
                    yield Ok(Event::default().event("tool").data(
                        serde_json::json!({
                            "tool": tool,
                            "emoji": emoji,
                            "label": narrated_label
                        }).to_string(),
                    ));
                }
            }
        }

        if full_response.trim().is_empty() {
            tracing::warn!("Hermes stream ended without tokens; falling back to non-streaming chat completion");
            let fallback = crate::hermes::generate_response(&prompt, &context, &config).await;
            if !fallback.trim().is_empty() {
                full_response.push_str(&fallback);
                sentence_buf.push_str(&fallback);
                yield Ok(Event::default().event("tok").data(fallback.clone()));
            }
        }

        if full_response.trim().is_empty() {
            let fallback = "Hermes no devolvió texto para esta respuesta. Prueba de nuevo.".to_string();
            full_response.push_str(&fallback);
            sentence_buf.push_str(&fallback);
            yield Ok(Event::default().event("tok").data(fallback));
        }

        let final_sentence = sentence_buf.trim();
        if final_sentence.len() > 1 {
            yield Ok(Event::default().event("sent").data(final_sentence.to_string()));
        }

        let message_id = db
            .add_message(&sid, "assistant", &full_response)
            .unwrap_or_else(|_| "unknown".to_string());

        yield Ok(Event::default().event("done").data(
            serde_json::json!({"session_id": sid, "message_id": message_id}).to_string(),
        ));
    };

    Ok(boxed_sse(event_stream))
}

pub fn chat_routes() -> Router<AppState> {
    Router::new()
        .route("/v1/chat/message", post(send_message))
        .route("/v1/chat/stream", post(stream_chat))
        .route("/v1/chat/ws", get(ws_chat))
        .route("/v1/chat/sessions", post(create_session))
        .route("/v1/chat/sessions", get(list_sessions))
        .route("/v1/chat/sessions/:id/messages", get(get_messages))
}

async fn maybe_persist_profile_update(state: &AppState, prompt: &str) -> Option<String> {
    if !looks_like_profile_update(prompt) {
        return None;
    }

    let current_config = state.config.load_full();
    let mut new_config = (*current_config).clone();
    new_config.system_prompt = replace_persistent_profile_block(&new_config.system_prompt, prompt);

    match persist_hermes_config(&new_config).await {
        Ok(()) => {
            state.config.store(Arc::new(new_config));
            Some("Listo, Nico. He guardado esa actualización en mi configuración persistente y la usaré en los próximos mensajes.".to_string())
        }
        Err(e) => Some(format!(
            "He entendido la actualización, pero no pude guardarla en la configuración persistente: {}",
            e
        )),
    }
}

fn looks_like_profile_update(prompt: &str) -> bool {
    let normalized = prompt.to_lowercase();
    [
        "actualiza tu info",
        "actualiza tu información",
        "actualiza tu informacion",
        "a partir de ahora",
        "desde ahora",
        "mi nombre ahora es",
        "ahora eres",
        "recuerda que",
    ]
    .iter()
    .any(|trigger| normalized.contains(trigger))
}

fn replace_persistent_profile_block(system_prompt: &str, update: &str) -> String {
    let mut base = system_prompt.to_string();
    if let Some(start) = base.find(PROFILE_BLOCK_START) {
        if let Some(end_offset) = base[start..].find(PROFILE_BLOCK_END) {
            let end = start + end_offset + PROFILE_BLOCK_END.len();
            base.replace_range(start..end, "");
        }
    }

    format!(
        "{}{}## Perfil persistente definido por el usuario\n{}\n{}",
        base.trim_end(),
        PROFILE_BLOCK_START,
        update.trim(),
        PROFILE_BLOCK_END
    )
}

fn narrate_tool_progress(tool: &str, label: &str) -> String {
    let detail = label.trim();
    let detail_suffix = if detail.is_empty() {
        String::new()
    } else {
        format!(": {}", detail)
    };

    match tool {
        "write_file" | "file.write" | "file_write" => {
            if detail.is_empty() {
                "Ahora voy a escribir el archivo".to_string()
            } else {
                format!("Ahora voy a escribir el archivo {}", detail)
            }
        }
        "read_file" | "file.read" | "file_read" => {
            if detail.is_empty() {
                "Ahora voy a leer el archivo".to_string()
            } else {
                format!("Ahora voy a leer {}", detail)
            }
        }
        "patch" | "apply_patch" | "file.patch" => {
            format!("Ahora voy a modificar archivos{}", detail_suffix)
        }
        "terminal" | "shell" | "bash" | "process" => {
            format!(
                "Ahora voy a ejecutar un comando en terminal{}",
                detail_suffix
            )
        }
        "web_search" | "search" | "web" => {
            format!("Ahora voy a buscar información en la web{}", detail_suffix)
        }
        "browser" | "navigate" | "click" | "type" => {
            format!("Ahora voy a usar el navegador{}", detail_suffix)
        }
        "execute_code" | "code_execution" => {
            format!("Ahora voy a ejecutar código{}", detail_suffix)
        }
        "vision" | "vision_analyze" => {
            format!("Ahora voy a analizar la imagen{}", detail_suffix)
        }
        "image_generate" | "image_gen" => {
            format!("Ahora voy a generar la imagen{}", detail_suffix)
        }
        "memory" | "memory.write" => {
            format!("Ahora voy a guardar esto en memoria{}", detail_suffix)
        }
        "todo" => format!("Ahora voy a actualizar la lista de tareas{}", detail_suffix),
        _ => {
            if detail.is_empty() || detail == tool {
                format!("Ahora voy a usar {}", tool)
            } else {
                format!("Ahora voy a usar {}: {}", tool, detail)
            }
        }
    }
}

fn boxed_sse<S>(stream: S) -> Sse<Pin<Box<dyn Stream<Item = Result<Event, Infallible>> + Send>>>
where
    S: Stream<Item = Result<Event, Infallible>> + Send + 'static,
{
    let boxed: Pin<Box<dyn Stream<Item = Result<Event, Infallible>> + Send>> = Box::pin(stream);
    Sse::new(boxed).keep_alive(KeepAlive::default())
}
