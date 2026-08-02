mod claude;
mod codex;
mod copilot;

pub use claude::{ClaudeCredentials, parse_claude_credentials, parse_claude_usage};
pub use codex::{CodexCredentials, parse_codex_credentials, parse_codex_usage};
pub use copilot::{next_copilot_reset, parse_copilot_usage};

#[derive(Debug, thiserror::Error)]
pub enum ParseError {
    #[error("invalid JSON: {0}")]
    InvalidJson(#[from] serde_json::Error),
    #[error("the provider response did not contain recognizable usage data")]
    UnrecognizedPayload,
    #[error("the local authentication file does not contain usable credentials")]
    MissingCredentials,
}
