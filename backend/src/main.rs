use arc_swap::ArcSwap;
use axum::Router;
use std::sync::Arc;
use tower_http::cors::{Any, CorsLayer};
use tower_http::trace::TraceLayer;
use tracing_subscriber::fmt::format::Writer;
use tracing_subscriber::fmt::time::FormatTime;
use tracing_subscriber::{fmt, layer::SubscriberExt, util::SubscriberInitExt};

#[derive(Clone)]
struct BackendTimer;

impl FormatTime for BackendTimer {
    fn format_time(&self, w: &mut Writer<'_>) -> std::fmt::Result {
        let now = chrono::Utc::now();
        write!(w, "[{}] [umi-backend]", now.format("%H:%M:%S"))
    }
}

mod auth;
mod config;
mod hermes;
mod routes;
mod services;

use config::Config;
use routes::{chat_routes, config_routes, health_routes, proxy_routes, tts_routes};
use services::SqliteService;

#[derive(Clone)]
pub struct AppState {
    pub db: Arc<SqliteService>,
    pub config: Arc<ArcSwap<Config>>,
}

#[tokio::main]
async fn main() {
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "umi_backend=info,tower_http=info".into()),
        )
        .with(
            fmt::layer()
                .with_timer(BackendTimer)
                .with_target(false)
                .with_level(false)
                .with_ansi(true),
        )
        .init();

    dotenvy::dotenv().ok();

    let config = Config::from_env();
    config.validate();

    let db = SqliteService::new(&config.db_path).expect("Failed to open SQLite database");

    let state = AppState {
        db: Arc::new(db),
        config: Arc::new(ArcSwap::from_pointee(config.clone())),
    };

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let app = Router::new()
        .merge(health_routes())
        .merge(chat_routes())
        .merge(proxy_routes())
        .merge(tts_routes())
        .merge(config_routes())
        .with_state(state)
        .layer(cors)
        .layer(TraceLayer::new_for_http());

    let addr = format!("0.0.0.0:{}", config.port);
    tracing::info!("Umi backend starting on {}", addr);

    let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
