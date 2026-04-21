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
use futures::StreamExt;
use serde::{Deserialize, Serialize};
use std::convert::Infallible;

use crate::AppState;

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

    // Load recent history for context
    let all_msgs = state.db.get_messages(&session_id).unwrap_or_default();
    let history: Vec<(String, String)> = all_msgs
        .iter()
        .map(|m| (m.role.clone(), m.content.clone()))
        .collect();

    // Limit to last 20, exclude the current prompt (hermes adds it)
    let start = if history.len() > 21 {
        history.len() - 21
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

    let response_text = crate::hermes::generate_response(&req.text, &context, &state.config).await;

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

    // 4. Load history for context (same logic as HTTP handler)
    let all_msgs = state.db.get_messages(&session_id).unwrap_or_default();
    let history: Vec<(String, String)> = all_msgs
        .iter()
        .map(|m| (m.role.clone(), m.content.clone()))
        .collect();
    let start = if history.len() > 21 {
        history.len() - 21
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
        crate::hermes::generate_response_stream(&req.text, &context, &state.config).await;

    let mut full_response = String::new();
    let mut sentence_buf = String::new();

    while let Some(token) = token_stream.next().await {
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
                    if sentence.len() > 1 {
                        let sent_msg = serde_json::json!({"t": "sent", "d": sentence}).to_string();
                        let _ = socket.send(Message::Text(sent_msg)).await;
                    }
                }
            }
        }
    }

    if full_response.trim().is_empty() {
        tracing::warn!("Hermes websocket stream ended without tokens; falling back to non-streaming chat completion");
        let fallback = crate::hermes::generate_response(&req.text, &context, &state.config).await;
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
) -> Result<Sse<impl futures::Stream<Item = Result<Event, Infallible>>>, StatusCode> {
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

    let all_msgs = state.db.get_messages(&session_id).unwrap_or_default();
    let history: Vec<(String, String)> = all_msgs
        .iter()
        .map(|m| (m.role.clone(), m.content.clone()))
        .collect();
    let start = if history.len() > 21 {
        history.len() - 21
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
    let config = state.config.clone();
    let db = state.db.clone();
    let sid = session_id.clone();

    let event_stream = async_stream::stream! {
        let mut token_stream =
            crate::hermes::generate_response_stream(&prompt, &context, &config).await;

        let mut full_response = String::new();
        let mut sentence_buf = String::new();

        while let Some(token) = token_stream.next().await {
            full_response.push_str(&token);
            sentence_buf.push_str(&token);

            yield Ok(Event::default().event("tok").data(&token));

            loop {
                match sentence_buf.find(|c: char| matches!(c, '.' | '!' | '?' | '\n')) {
                    None => break,
                    Some(pos) => {
                        let sentence = sentence_buf[..=pos].trim().to_string();
                        sentence_buf = sentence_buf[pos + 1..].to_string();
                        if sentence.len() > 1 {
                            yield Ok(Event::default().event("sent").data(sentence));
                        }
                    }
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

    Ok(Sse::new(event_stream).keep_alive(KeepAlive::default()))
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
