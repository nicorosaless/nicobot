use axum::{
    async_trait,
    extract::FromRequestParts,
    http::{request::Parts, StatusCode},
};

/// Local user — no auth needed for single-user local app.
#[derive(Clone)]
pub struct AuthUser {
    pub uid: String,
}

#[async_trait]
impl<S> FromRequestParts<S> for AuthUser
where
    S: Send + Sync,
{
    type Rejection = StatusCode;

    async fn from_request_parts(_parts: &mut Parts, _state: &S) -> Result<Self, Self::Rejection> {
        Ok(AuthUser {
            uid: "local".to_string(),
        })
    }
}
