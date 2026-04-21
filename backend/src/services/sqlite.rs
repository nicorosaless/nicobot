use chrono::Utc;
use rusqlite::{params, Connection, Result};
use std::sync::Mutex;
use uuid::Uuid;

pub struct SqliteService {
    conn: Mutex<Connection>,
}

impl SqliteService {
    pub fn new(db_path: &str) -> Result<Self> {
        let conn = Connection::open(db_path)?;
        let svc = Self {
            conn: Mutex::new(conn),
        };
        svc.migrate()?;
        Ok(svc)
    }

    fn migrate(&self) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute_batch("
            CREATE TABLE IF NOT EXISTS chat_sessions (
                id TEXT PRIMARY KEY,
                title TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS chat_messages (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY (session_id) REFERENCES chat_sessions(id)
            );
            CREATE INDEX IF NOT EXISTS idx_messages_session ON chat_messages(session_id, created_at);
        ")
    }

    pub fn create_session(&self, title: Option<&str>) -> Result<String> {
        let id = Uuid::new_v4().to_string();
        let now = Utc::now().to_rfc3339();
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO chat_sessions (id, title, created_at, updated_at) VALUES (?1, ?2, ?3, ?4)",
            params![id, title.unwrap_or("Nueva conversación"), now, now],
        )?;
        Ok(id)
    }

    pub fn list_sessions(&self) -> Result<Vec<ChatSession>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, title, created_at, updated_at FROM chat_sessions ORDER BY updated_at DESC",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok(ChatSession {
                id: row.get(0)?,
                title: row.get(1)?,
                created_at: row.get(2)?,
                updated_at: row.get(3)?,
            })
        })?;
        rows.collect()
    }

    pub fn add_message(&self, session_id: &str, role: &str, content: &str) -> Result<String> {
        let id = Uuid::new_v4().to_string();
        let now = Utc::now().to_rfc3339();
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO chat_messages (id, session_id, role, content, created_at) VALUES (?1, ?2, ?3, ?4, ?5)",
            params![id, session_id, role, content, now],
        )?;
        conn.execute(
            "UPDATE chat_sessions SET updated_at = ?1 WHERE id = ?2",
            params![now, session_id],
        )?;
        Ok(id)
    }

    pub fn get_messages(&self, session_id: &str) -> Result<Vec<ChatMessage>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, session_id, role, content, created_at FROM chat_messages WHERE session_id = ?1 ORDER BY created_at ASC"
        )?;
        let rows = stmt.query_map(params![session_id], |row| {
            Ok(ChatMessage {
                id: row.get(0)?,
                session_id: row.get(1)?,
                role: row.get(2)?,
                content: row.get(3)?,
                created_at: row.get(4)?,
            })
        })?;
        rows.collect()
    }
}

#[derive(serde::Serialize)]
pub struct ChatSession {
    pub id: String,
    pub title: String,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(serde::Serialize)]
pub struct ChatMessage {
    pub id: String,
    pub session_id: String,
    pub role: String,
    pub content: String,
    pub created_at: String,
}
