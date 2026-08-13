mod claude;
mod codex;
mod copilot;

use chrono::{DateTime, Utc};

use crate::models::{ProviderAuthState, ProviderId, ProviderSnapshot};

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

pub async fn current_auth_state(
    provider: ProviderId,
    copilot_token_present: bool,
    claude_credentials_json: Option<&str>,
) -> ProviderAuthState {
    match provider {
        ProviderId::Codex => codex::load_credentials().map_or(ProviderAuthState::SignedOut, |_| {
            ProviderAuthState::Configured
        }),
        ProviderId::Claude => claude::load_credentials(claude_credentials_json)
            .map_or(ProviderAuthState::SignedOut, |_| {
                ProviderAuthState::Configured
            }),
        ProviderId::Copilot => {
            if copilot_token_present {
                ProviderAuthState::Configured
            } else {
                ProviderAuthState::SignedOut
            }
        }
    }
}

pub async fn refresh_provider(
    provider: ProviderId,
    copilot_token: Option<&str>,
    claude_credentials_json: Option<&str>,
    now: DateTime<Utc>,
) -> ProviderSnapshot {
    match provider {
        ProviderId::Codex => codex::refresh(now).await,
        ProviderId::Claude => claude::refresh(claude_credentials_json, now).await,
        ProviderId::Copilot => copilot::refresh(copilot_token, now).await,
    }
}
