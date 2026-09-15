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
        None => fs::read(credentials_path()).map_err(classify_credentials_read_error)?,
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
                "Claude needs you to sign in again to access usage data.".to_owned(),
            ),
            base_metrics,
            now,
        );
    }
    if credentials.is_expired_at(now) {
        return failed_snapshot(
            ProviderError::InvalidAuth("Claude needs you to sign in again.".to_owned()),
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
            "Claude needs you to sign in again.".to_owned(),
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

fn classify_credentials_read_error(error: std::io::Error) -> ProviderError {
    if error.kind() == std::io::ErrorKind::NotFound {
        ProviderError::MissingAuth("Claude needs you to sign in.".to_owned())
    } else {
        ProviderError::CredentialAccess(format!(
            "Claude credentials could not be read. Check file access and retry: {error}"
        ))
    }
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
        auth_state: if matches!(
            error,
            ProviderError::MissingAuth(_) | ProviderError::InvalidAuth(_)
        ) {
            ProviderAuthState::SignedOut
        } else {
            ProviderAuthState::Configured
        },
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

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn expired_credentials_require_sign_in() {
        let snapshot = refresh(Some(r#"{"claudeAiOauth":{"accessToken":"expired","scopes":["user:profile"],"expiresAt":1}}"#), Utc::now()).await;

        assert_eq!(snapshot.auth_state, ProviderAuthState::SignedOut);
        assert_eq!(snapshot.fetch_state, ProviderFetchState::Failed);
    }

    #[tokio::test]
    async fn missing_usage_scope_requires_sign_in() {
        let snapshot = refresh(
            Some(r#"{"claudeAiOauth":{"accessToken":"token","scopes":[]}}"#),
            Utc::now(),
        )
        .await;

        assert_eq!(snapshot.auth_state, ProviderAuthState::SignedOut);
    }

    #[test]
    fn usage_errors_preserve_configured_auth() {
        for error in [
            ProviderError::Network("offline".into()),
            ProviderError::InvalidResponse("HTTP 429".into()),
        ] {
            let snapshot = failed_snapshot(error, vec![], Utc::now());

            assert_eq!(snapshot.auth_state, ProviderAuthState::Configured);
            assert_eq!(snapshot.fetch_state, ProviderFetchState::Failed);
        }
    }

    #[test]
    fn credential_access_failure_does_not_require_sign_in() {
        let error = classify_credentials_read_error(std::io::Error::from(
            std::io::ErrorKind::PermissionDenied,
        ));
        assert!(matches!(error, ProviderError::CredentialAccess(_)));

        let snapshot = failed_snapshot(error, vec![], Utc::now());
        assert_eq!(snapshot.auth_state, ProviderAuthState::Configured);
        assert_eq!(snapshot.fetch_state, ProviderFetchState::Failed);
    }

    #[test]
    fn rejected_credentials_require_sign_in() {
        let snapshot = failed_snapshot(
            ProviderError::InvalidAuth("HTTP 401".into()),
            vec![],
            Utc::now(),
        );

        assert_eq!(snapshot.auth_state, ProviderAuthState::SignedOut);
    }
}
