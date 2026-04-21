pub mod chat;
pub mod config;
pub mod health;
pub mod proxy;
pub mod tts;

pub use chat::chat_routes;
pub use config::config_routes;
pub use health::health_routes;
pub use proxy::proxy_routes;
pub use tts::tts_routes;
