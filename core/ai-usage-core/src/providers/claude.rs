use std::{env, fs, path::PathBuf};

use chrono::{DateTime, Utc};

use crate::{
    models::{
        ProviderAuthState, ProviderFetchState, ProviderId, ProviderSnapshot, UsageMetric,
        UsageMetricKind,
    },
    parsers::{ClaudeCredentials, parse_claude_credentials, parse_claude_usage},
};

use super::ProviderError;

const USAGE_URL: &str = "https://api.anthropic.com/api/oauth/usage";

pub fn load_credentials(
    supplied_credentials_json: Option<&str>,
) -> Result<ClaudeCredentials, ProviderError> {
    let data = match supplied_credentials_json {
        Some(credentials) => credentials.as_bytes().to_vec(),
        None => fs::read(credentials_path()).map_err(|_| {
            ProviderError::MissingAuth(
                "Claude Code auth was not found. Run `claude` and refresh.".to_owned(),
            )
        })?,
    };
    parse_claude_credentials(&data).map_err(|error| ProviderError::InvalidAuth(error.to_string()))
}

pub async fn refresh(
    supplied_credentials_json: Option<&str>,
    now: DateTime<Utc>,
) -> ProviderSnapshot {
    let base_metrics = vec![
        UsageMetric::unavailable(UsageMetricKind::ClaudeFiveHour, now),
        UsageMetric::unavailable(UsageMetricKind::ClaudeWeekly, now),
    ];
    let credentials = match load_credentials(supplied_credentials_json) {
        Ok(credentials) => credentials,
        Err(ProviderError::MissingAuth(_)) | Err(ProviderError::InvalidAuth(_)) => {
            return ProviderSnapshot {
                provider: ProviderId::Claude,
                auth_state: ProviderAuthState::SignedOut,
                fetch_state: ProviderFetchState::MissingAuth,
                fetched_at_utc: None,
                metrics: base_metrics,
                error_description: None,
                source_description: Some("Local Claude Code OAuth auth".to_owned()),
            };
        }
        Err(error) => return failed_snapshot(error, base_metrics, now),
    };

    if !credentials.has_usage_scope() {
        return failed_snapshot(
            ProviderError::InvalidAuth(
                "Claude Code auth is missing the scope needed for usage data. Run `claude` again."
                    .to_owned(),
            ),
            base_metrics,
            now,
        );
    }
    if credentials.is_expired_at(now) {
        return failed_snapshot(
            ProviderError::InvalidAuth(
                "Claude Code auth expired. Run `claude` again and refresh.".to_owned(),
            ),
            base_metrics,
            now,
        );
    }

    match fetch_usage(&credentials.access_token, now).await {
        Ok(metrics) => ProviderSnapshot {
            provider: ProviderId::Claude,
            auth_state: ProviderAuthState::Authenticated,
            fetch_state: ProviderFetchState::Ok,
            fetched_at_utc: Some(now),
            metrics,
            error_description: None,
            source_description: Some("Local Claude Code OAuth auth".to_owned()),
        },
        Err(error) => failed_snapshot(error, base_metrics, now),
    }
}

async fn fetch_usage(
    access_token: &str,
    now: DateTime<Utc>,
) -> Result<Vec<UsageMetric>, ProviderError> {
    let response = reqwest::Client::new()
        .get(USAGE_URL)
        .bearer_auth(access_token)
        .header("Accept", "application/json")
        .header("Content-Type", "application/json")
        .header("anthropic-beta", "oauth-2025-04-20")
        .header("User-Agent", "claude-code/2.1.0")
        .timeout(std::time::Duration::from_secs(30))
        .send()
        .await
        .map_err(network_error)?;
    let status = response.status();
    let data = response.bytes().await.map_err(network_error)?;

    if status == reqwest::StatusCode::UNAUTHORIZED {
        return Err(ProviderError::InvalidAuth(
            "Claude Code auth is no longer valid. Run `claude` again and refresh.".to_owned(),
        ));
    }
    if !status.is_success() {
        return Err(ProviderError::InvalidResponse(format!(
            "Claude usage API returned HTTP {}: {}",
            status.as_u16(),
            String::from_utf8_lossy(&data)
        )));
    }

    parse_claude_usage(&data, now)
        .map_err(|error| ProviderError::InvalidResponse(error.to_string()))
}

fn credentials_path() -> PathBuf {
    let config_root = env::var("CLAUDE_CONFIG_DIR")
        .ok()
        .and_then(|value| value.split(',').next().map(str::trim).map(str::to_owned))
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home_directory().join(".claude"));
    config_root.join(".credentials.json")
}

fn home_directory() -> PathBuf {
    env::var_os("USERPROFILE")
        .or_else(|| env::var_os("HOME"))
        .map(PathBuf::from)
        .unwrap_or_default()
}

fn failed_snapshot(
    error: ProviderError,
    metrics: Vec<UsageMetric>,
    now: DateTime<Utc>,
) -> ProviderSnapshot {
    ProviderSnapshot {
        provider: ProviderId::Claude,
        auth_state: ProviderAuthState::Configured,
        fetch_state: ProviderFetchState::Failed,
        fetched_at_utc: Some(now),
        metrics,
        error_description: Some(error.to_string()),
        source_description: Some("Local Claude Code OAuth auth".to_owned()),
    }
}

fn network_error(error: reqwest::Error) -> ProviderError {
    ProviderError::Network(format!("Claude usage request failed: {error}"))
}
