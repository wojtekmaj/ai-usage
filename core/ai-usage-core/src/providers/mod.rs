mod claude;
mod codex;
mod copilot;

use chrono::{DateTime, Utc};

use crate::models::ProviderSnapshot;

pub use copilot::{
    CopilotDeviceCode, CopilotPollResult, poll_copilot_token, request_copilot_device_code,
};

pub async fn preheat_codex() -> Result<(), ProviderError> {
    codex::preheat().await
}

#[derive(Debug, thiserror::Error)]
pub enum ProviderError {
    #[error("{0}")]
    MissingAuth(String),
    #[error("{0}")]
    InvalidAuth(String),
    #[error("{0}")]
    Network(String),
    #[error("{0}")]
    InvalidResponse(String),
}

pub async fn refresh_all(
    copilot_token: Option<&str>,
    claude_credentials_json: Option<&str>,
    now: DateTime<Utc>,
) -> Vec<ProviderSnapshot> {
    let (codex, claude, copilot) = tokio::join!(
        codex::refresh(now),
        claude::refresh(claude_credentials_json, now),
        copilot::refresh(copilot_token, now),
    );
    vec![codex, claude, copilot]
}
