# Roadmap Umi

## Principio: Local-first, Cloud LLM

Todo corre en tu Mac. La única conexión a internet es la llamada al LLM (OpenAI, Anthropic, Gemini). Datos nunca salen de tu máquina excepto el prompt y contexto enviado al LLM. Sin telemetría, sin analytics, sin cuentas de usuario.

| Local | Cloud |
|---|---|
| App (SwiftUI nativa) | LLM API (OpenAI/Anthropic/Gemini) |
| Backend (Rust/Axum en localhost) | |
| Persistencia (SQLite) | |
| Configuración (UserDefaults + .env) | |
| STT futuro (whisper.cpp) | |
| TTS futuro (local o key del usuario) | |

---

## Origen

Fork de [Omi desktop](https://github.com/BasedHardware/omi) (MIT, abril 2026). Se preservó la UI (SwiftUI + floating bar) y se reemplazó todo el backend cloud (Firebase, Firestore, Redis, analytics) por un stack local (Rust/Axum + SQLite).

---

## Completado

### Fork y limpieza (Phases 0-5)

- ✅ Legacy (Electron + Python) movido a `legacy/`
- ✅ Omi desktop source importado → `frontend/` + `backend/`
- ✅ Firebase, Sentry, Mixpanel, PostHog, Heap, Sparkle eliminados
- ✅ Frontend compila limpio (SwiftUI, 0 errors, 0 warnings)
- ✅ Backend compila y corre (Rust/Axum, health + chat endpoints)
- ✅ Auth stub (siempre signed-in), analytics stub (no-op)
- ✅ Sidebar reducida a Chat + Settings
- ✅ BYOK UI en Settings (OpenAI, Anthropic, Gemini keys)
- ✅ ChatProvider + APIClient apuntando a localhost:10201
- ✅ FloatingControlBar preservada (Ask Umi, PTT state machine, shortcuts)
- ✅ Hermes agent stub (keyword-matching en Rust)
- ✅ SQLite para sesiones y mensajes

---

## Alpha (v0.1) — Próximo

Objetivo: **Cmd+Shift+Space → pregunta → respuesta del LLM**

| Tarea | Descripción |
|---|---|
| ✅ Conectar Hermes a LLM real | Backend conectado al Hermes Agent local por API Server (`/v1/chat/completions`), con fallback directo/no-streaming. |
| ✅ Streaming de chat | `/v1/chat/stream` emite `tok`, `sent` y `done`; UI muestra respuesta progresiva y re-streaming visual si cae a fallback. |
| ✅ Preparar contrato TTS | `tok` queda listo para UI/TTS token a token y `sent` para síntesis por segmentos; TTS real no entra todavía. |
| ✅ Simplificar run.sh | Build backend + frontend, launch, Ctrl+C mata servicios locales; arranca Hermes con variables oficiales del API Server. |
| Bundle config | Info.plist con nombre "Umi", bundle ID, entitlements mínimos. |
| ✅ E2E smoke test | `./run.sh` → app abre → backend/Hermes healthy → chat → respuesta LLM visible con streaming progresivo. |

Criterio de done: alguien con el repo clonado y una API key puede hacer `./run.sh` y chatear con un LLM desde la floating bar.

---

## v0.2 — Contexto visual

Objetivo: **el LLM puede ver tu pantalla cuando preguntas**

| Tarea | Descripción |
|---|---|
| Screen capture | Captura de pantalla local al enviar prompt (ya tiene stub en `ScreenCaptureManager.swift`). |
| Envío al LLM | Adjuntar screenshot como imagen en la llamada al LLM (vision API). |
| Permisos macOS | Solicitar Screen Recording permission en el primer uso. |
| UX | Indicador visual de que la captura se adjuntó al prompt. |

---

## v0.3 — Voz local

Objetivo: **hablar con Umi sin salir del teclado**

| Tarea | Descripción |
|---|---|
| STT local | whisper.cpp o similar — sin cloud. PTT state machine ya existe. |
| TTS local | Sintetizar respuestas con voz local (o key del usuario para ElevenLabs). |
| Wire PTT completo | Conectar `PushToTalkManager` → STT → prompt → LLM → TTS. |

---

## v1.0 — Distribución

| Tarea | Descripción |
|---|---|
| DMG / Homebrew | Packaging para distribución sin Xcode. |
| Onboarding | 1-2 pantallas: bienvenida + API key. |
| Auto-update | Mecanismo simple (git pull o Sparkle sin analytics). |

---

## Archivos clave

| Archivo | Rol |
|---|---|
| `backend/src/hermes.rs` | Agent: stub → LLM real |
| `backend/src/routes/chat.rs` | Endpoint principal `/v1/chat/message` |
| `backend/src/config.rs` | `LLM_API_KEY`, `LLM_API_URL`, `LLM_MODEL` |
| `frontend/Sources/ChatProvider.swift` | Estado de chat, llamadas al backend |
| `frontend/Sources/FloatingControlBar/` | Floating bar, PTT, shortcuts |
| `run.sh` | Build & launch script |
