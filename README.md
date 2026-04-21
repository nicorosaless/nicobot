# Umi

Umi es un asistente de escritorio nativo para macOS. Forked desde [Omi](https://github.com/BasedHardware/omi) (MIT), reemplazando el engine cloud por un stack 100% local: SwiftUI + Rust/Axum + SQLite.

## Estado actual

| Componente | Estado | Notas |
|---|---|---|
| Frontend (SwiftUI) | ✅ Compila | Floating bar, chat page, settings, BYOK |
| Backend (Rust/Axum) | ✅ Compila y corre | Health, chat, proxy LLM, SQLite |
| Hermes agent | ✅ Integrado | Sidecar via NousResearch hermes-agent (Fireworks AI default) |
| Push-to-talk | ⚠️ UI lista | State machine + shortcuts OK; STT no conectado |
| TTS | ❌ Stub | Interfaz preservada, sin implementación |
| Screen capture | ❌ Stub | Interfaz preservada, sin implementación |
| run.sh | ✅ Reescrito | ~120 líneas: venv + Hermes sidecar + backend + frontend + app |

## Estructura del repo

```
umi/
├── frontend/          # SwiftUI macOS app (44 .swift files)
│   ├── Package.swift
│   └── Sources/
│       ├── UmiApp.swift              # Entry point (@main)
│       ├── FloatingControlBar/       # Floating bar + PTT + shortcuts
│       ├── MainWindow/               # Chat page, settings, sidebar
│       ├── ChatProvider.swift        # Estado de chat → backend
│       ├── APIClient.swift           # HTTP client → localhost:10201
│       └── Theme/                    # Colores, fuentes, chrome
├── backend/           # Rust/Axum REST API (12 .rs files)
│   ├── Cargo.toml
│   └── src/
│       ├── main.rs                   # Entry point, routes, CORS
│       ├── hermes.rs                 # Agent stub (keyword-matching)
│       ├── routes/                   # health, chat, proxy, tts, config
│       └── services/sqlite.rs        # Sessions + messages persistence
├── legacy/            # Electron + Python anterior (deprecated)
├── docs/              # Producto, arquitectura, roadmap
├── run.sh             # Build & launch script (pendiente de simplificar)
└── .env.example       # Configuración mínima
```

## Quick start (manual, hasta que run.sh esté listo)

### Requisitos

- macOS 14+
- Rust (`curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`)
- Xcode Command Line Tools (`xcode-select --install`)

### 1. Backend

```bash
cp backend/.env.example backend/.env
# Añadir HERMES_API_KEY en backend/.env (Fireworks AI key para respuestas reales)
cargo run --manifest-path backend/Cargo.toml
```

Verificar: `curl http://localhost:10201/health`

### 2. Frontend

```bash
xcrun swift build -c debug --package-path frontend
```

### 3. Chat via API (sin UI por ahora)

```bash
curl -X POST http://localhost:10201/v1/chat/message \
  -H "Content-Type: application/json" \
  -d '{"text": "hola"}'
```

## Tech stack

- **Frontend:** SwiftUI (macOS 14+), MarkdownUI, GRDB.swift, ONNX Runtime (VAD)
- **Backend:** Rust, Axum, rusqlite, reqwest, tokio
- **LLM:** NousResearch Hermes Agent sidecar, configurable via `HERMES_API_KEY` (default: Fireworks AI)
- **Persistencia:** SQLite local (backend) + UserDefaults (frontend)

## Documentación

- [Visión de producto](docs/product/vision.md)
- [Roadmap del fork Umi](docs/roadmap/umi-fork-roadmap.md)
- [Definición de alpha](docs/roadmap/alpha-definition.md)
- [Licencias de terceros](docs/THIRD_PARTY_LICENSES.md)

## Referencias externas

- [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) — sidecar de agente, documentación de config y tools
