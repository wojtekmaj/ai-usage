use std::{env, fs, path::PathBuf, process::Stdio, time::Duration};

use chrono::{DateTime, TimeDelta, Utc};
use reqwest::StatusCode;
use serde_json::{Value, json};

use crate::{
    models::{
        ProviderAuthState, ProviderFetchState, ProviderId, ProviderSnapshot, UsageMetric,
        UsageMetricKind,
    },
    parsers::{CodexCredentials, parse_codex_credentials, parse_codex_usage},
};

use super::ProviderError;

const DEFAULT_BASE_URL: &str = "https://chatgpt.com/backend-api/";
const REFRESH_URL: &str = "https://auth.openai.com/oauth/token";
const CLIENT_ID: &str = "app_EMoamEEZ73f0CkXaXp7hrann";
const PREHEAT_PROMPT: &str = "Reply with exactly: pong. Do not use tools.";
const PREHEAT_TIMEOUT: Duration = Duration::from_secs(90);

pub async fn preheat() -> Result<(), ProviderError> {
    let executable = codex_executable().ok_or_else(|| {
        ProviderError::InvalidResponse(
            "Codex could not be found. Install the Codex app or CLI and try again.".to_owned(),
        )
    })?;
    let mut command = tokio::process::Command::new(executable);
    command
        .args([
            "exec",
            "--ephemeral",
            "--ignore-user-config",
            "--ignore-rules",
            "--skip-git-repo-check",
            "--sandbox",
            "read-only",
            "--color",
            "never",
            PREHEAT_PROMPT,
        ])
        .current_dir(env::temp_dir())
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);

    let output = tokio::time::timeout(PREHEAT_TIMEOUT, command.output())
        .await
        .map_err(|_| {
            ProviderError::Network(format!(
                "Codex preheat timed out after {} seconds.",
                PREHEAT_TIMEOUT.as_secs()
            ))
        })?
        .map_err(|error| {
            ProviderError::InvalidResponse(format!("Codex preheat could not start: {error}"))
        })?;

    if output.status.success() {
        return Ok(());
    }

    let detail = String::from_utf8_lossy(&output.stderr).trim().to_owned();
    let detail = if detail.is_empty() {
        format!("Codex exited with status {}.", output.status)
    } else {
        detail
    };
    Err(ProviderError::InvalidResponse(format!(
        "Codex preheat failed: {detail}"
    )))
}

fn codex_executable() -> Option<PathBuf> {
    let executable_names = if cfg!(windows) {
        vec!["codex.exe", "codex.cmd"]
    } else {
        vec!["codex"]
    };
    let mut candidates = Vec::new();

    if let Some(configured) =
        env::var_os("AI_USAGE_CODEX_EXECUTABLE").filter(|value| !value.is_empty())
    {
        candidates.push(PathBuf::from(configured));
    }
    if let Some(path) = env::var_os("PATH") {
        candidates.extend(env::split_paths(&path).flat_map(|directory| {
            executable_names
                .iter()
                .map(move |executable_name| directory.join(executable_name))
        }));
    }

    let home = home_directory();
    candidates.extend([
        home.join(".local/bin/codex"),
        home.join("Applications/ChatGPT.app/Contents/Resources/codex"),
        home.join("Applications/Codex.app/Contents/Resources/codex"),
        PathBuf::from("/Applications/ChatGPT.app/Contents/Resources/codex"),
        PathBuf::from("/Applications/Codex.app/Contents/Resources/codex"),
        PathBuf::from("/usr/local/bin/codex"),
        PathBuf::from("/opt/homebrew/bin/codex"),
    ]);

    if let Some(local_app_data) = env::var_os("LOCALAPPDATA").filter(|value| !value.is_empty()) {
        let local_app_data = PathBuf::from(local_app_data);
        candidates.extend([
            local_app_data.join("Programs/ChatGPT/resources/codex.exe"),
            local_app_data.join("Programs/Codex/resources/codex.exe"),
            local_app_data.join("Microsoft/WindowsApps/codex.exe"),
        ]);
    }
    if let Some(app_data) = env::var_os("APPDATA").filter(|value| !value.is_empty()) {
        candidates.push(PathBuf::from(app_data).join("npm/codex.cmd"));
    }

    candidates.into_iter().find(|candidate| candidate.is_file())
}

pub fn load_credentials() -> Result<CodexCredentials, ProviderError> {
    let data = fs::read(auth_path()).map_err(|_| {
        ProviderError::MissingAuth(
            "Codex auth was not found. Sign in to the Codex desktop app, or run `codex login`, then refresh."
                .to_owned(),
        )
    })?;
    parse_codex_credentials(&data).map_err(|error| ProviderError::InvalidAuth(error.to_string()))
}

pub async fn refresh(now: DateTime<Utc>) -> ProviderSnapshot {
    let base_metrics = [
        UsageMetricKind::CodexFiveHour,
        UsageMetricKind::CodexWeekly,
        UsageMetricKind::CodexSparkFiveHour,
        UsageMetricKind::CodexSparkWeekly,
        UsageMetricKind::CodexCredits,
    ]
    .into_iter()
    .map(|kind| UsageMetric::unavailable(kind, now))
    .collect::<Vec<_>>();

    let mut credentials = match load_credentials() {
        Ok(credentials) => credentials,
        Err(ProviderError::MissingAuth(_)) | Err(ProviderError::InvalidAuth(_)) => {
            return ProviderSnapshot {
                provider: ProviderId::Codex,
                auth_state: ProviderAuthState::SignedOut,
                fetch_state: ProviderFetchState::MissingAuth,
                fetched_at_utc: None,
                metrics: base_metrics,
                error_description: None,
                source_description: Some("Local Codex auth".to_owned()),
            };
        }
        Err(error) => return failed_snapshot(error, base_metrics, now),
    };

    if credentials_needs_refresh(&credentials, now) {
        match refresh_credentials(&credentials, now).await {
            Ok(refreshed) => {
                if let Err(error) = save_credentials(&refreshed) {
                    return failed_snapshot(error, base_metrics, now);
                }
                credentials = refreshed;
            }
            Err(error) => return failed_snapshot(error, base_metrics, now),
        }
    }

    match fetch_usage(&credentials, now).await {
        Ok(metrics) => ProviderSnapshot {
            provider: ProviderId::Codex,
            auth_state: ProviderAuthState::Authenticated,
            fetch_state: ProviderFetchState::Ok,
            fetched_at_utc: Some(now),
            metrics,
            error_description: None,
            source_description: Some("Local Codex auth".to_owned()),
        },
        Err(error) => failed_snapshot(error, base_metrics, now),
    }
}

fn credentials_needs_refresh(credentials: &CodexCredentials, now: DateTime<Utc>) -> bool {
    if credentials.refresh_token.is_empty() {
        return false;
    }
    credentials
        .last_refresh
        .is_none_or(|last_refresh| now - last_refresh > TimeDelta::days(8))
}

async fn refresh_credentials(
    credentials: &CodexCredentials,
    now: DateTime<Utc>,
) -> Result<CodexCredentials, ProviderError> {
    let response = reqwest::Client::new()
        .post(REFRESH_URL)
        .json(&json!({
            "client_id": CLIENT_ID,
            "grant_type": "refresh_token",
            "refresh_token": credentials.refresh_token,
            "scope": "openid profile email"
        }))
        .timeout(Duration::from_secs(30))
        .send()
        .await
        .map_err(network_error)?;
    let status = response.status();
    let payload: Value = response.json().await.map_err(network_error)?;
    if status == StatusCode::UNAUTHORIZED {
        let code = payload
            .pointer("/error/code")
            .or_else(|| payload.get("error"))
            .or_else(|| payload.get("code"))
            .and_then(Value::as_str)
            .unwrap_or_default();
        let message = match code.to_lowercase().as_str() {
            "refresh_token_reused" => {
                "Codex refresh token was already used. Sign in to Codex again."
            }
            "refresh_token_invalidated" => {
                "Codex refresh token was revoked. Sign in to Codex again."
            }
            _ => "Codex refresh token expired. Sign in to Codex again.",
        };
        return Err(ProviderError::InvalidAuth(message.to_owned()));
    }
    if !status.is_success() {
        return Err(ProviderError::InvalidResponse(format!(
            "Codex auth refresh failed with HTTP {}.",
            status.as_u16()
        )));
    }

    Ok(CodexCredentials {
        access_token: string_at(&payload, "access_token")
            .unwrap_or_else(|| credentials.access_token.clone()),
        refresh_token: string_at(&payload, "refresh_token")
            .unwrap_or_else(|| credentials.refresh_token.clone()),
        id_token: string_at(&payload, "id_token").or_else(|| credentials.id_token.clone()),
        account_id: credentials.account_id.clone(),
        last_refresh: Some(now),
    })
}

fn save_credentials(credentials: &CodexCredentials) -> Result<(), ProviderError> {
    let path = auth_path();
    let data = fs::read(&path).map_err(|error| {
        ProviderError::InvalidAuth(format!("Codex auth could not be read: {error}"))
    })?;
    let mut root: Value = serde_json::from_slice(&data).map_err(|error| {
        ProviderError::InvalidAuth(format!("Codex auth could not be decoded: {error}"))
    })?;
    root["tokens"]["access_token"] = Value::String(credentials.access_token.clone());
    root["tokens"]["refresh_token"] = Value::String(credentials.refresh_token.clone());
    if let Some(id_token) = &credentials.id_token {
        root["tokens"]["id_token"] = Value::String(id_token.clone());
    }
    if let Some(account_id) = &credentials.account_id {
        root["tokens"]["account_id"] = Value::String(account_id.clone());
    }
    root["last_refresh"] = Value::String(
        credentials
            .last_refresh
            .unwrap_or_else(Utc::now)
            .to_rfc3339(),
    );
    let encoded = serde_json::to_vec_pretty(&root).map_err(|error| {
        ProviderError::InvalidAuth(format!("Codex auth could not be encoded: {error}"))
    })?;
    fs::write(path, encoded).map_err(|error| {
        ProviderError::InvalidAuth(format!("Codex auth could not be saved: {error}"))
    })
}

async fn fetch_usage(
    credentials: &CodexCredentials,
    now: DateTime<Utc>,
) -> Result<Vec<UsageMetric>, ProviderError> {
    let base_url = chatgpt_base_url();
    let usage_url = if base_url.contains("/backend-api/") {
        format!("{base_url}wham/usage")
    } else {
        format!("{base_url}api/codex/usage")
    };
    let client = reqwest::Client::new();
    let mut request = client
        .get(&usage_url)
        .bearer_auth(&credentials.access_token)
        .header("Accept", "application/json")
        .header("User-Agent", "AI Usage")
        .timeout(Duration::from_secs(30));
    if let Some(account_id) = &credentials.account_id {
        request = request.header("ChatGPT-Account-Id", account_id);
    }
    let response = request.send().await.map_err(network_error)?;
    let status = response.status();
    let mut payload: Value = response.json().await.map_err(network_error)?;
    validate_status(status, "Codex usage API")?;

    if base_url.contains("/backend-api/") {
        let reset_url = format!("{base_url}wham/rate-limit-reset-credits");
        let mut reset_request = client
            .get(reset_url)
            .bearer_auth(&credentials.access_token)
            .header("Accept", "application/json")
            .header("User-Agent", "AI Usage")
            .timeout(Duration::from_secs(30));
        if let Some(account_id) = &credentials.account_id {
            reset_request = reset_request.header("ChatGPT-Account-Id", account_id);
        }
        if let Ok(response) = reset_request.send().await
            && response.status().is_success()
            && let Ok(reset_payload) = response.json::<Value>().await
        {
            payload["rate_limit_reset_credits"] = reset_payload;
        }
    }

    parse_codex_usage(&payload, now)
        .map_err(|error| ProviderError::InvalidResponse(error.to_string()))
}

fn validate_status(status: StatusCode, source: &str) -> Result<(), ProviderError> {
    if status.is_success() {
        Ok(())
    } else if matches!(status, StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN) {
        Err(ProviderError::InvalidAuth(
            "Codex auth is no longer valid. Sign in to Codex and refresh.".to_owned(),
        ))
    } else {
        Err(ProviderError::InvalidResponse(format!(
            "{source} returned HTTP {}.",
            status.as_u16()
        )))
    }
}

fn auth_path() -> PathBuf {
    codex_home().join("auth.json")
}

fn codex_home() -> PathBuf {
    env::var_os("CODEX_HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home_directory().join(".codex"))
}

fn home_directory() -> PathBuf {
    env::var_os("USERPROFILE")
        .or_else(|| env::var_os("HOME"))
        .map(PathBuf::from)
        .unwrap_or_default()
}

fn chatgpt_base_url() -> String {
    let config_path = codex_home().join("config.toml");
    let configured = fs::read_to_string(config_path)
        .ok()
        .and_then(|content| configured_base_url(&content));
    normalize_base_url(configured.as_deref().unwrap_or(DEFAULT_BASE_URL))
}

fn configured_base_url(config: &str) -> Option<String> {
    config.lines().find_map(|line| {
        let line = line.split('#').next()?.trim();
        let (key, value) = line.split_once('=')?;
        (key.trim() == "chatgpt_base_url").then(|| {
            value
                .trim()
                .trim_matches(|character| character == '"' || character == '\'')
                .to_owned()
        })
    })
}

fn normalize_base_url(value: &str) -> String {
    let mut normalized = value.trim().trim_end_matches('/').to_owned();
    if normalized.is_empty() {
        normalized = DEFAULT_BASE_URL.trim_end_matches('/').to_owned();
    }
    if (normalized.starts_with("https://chatgpt.com")
        || normalized.starts_with("https://chat.openai.com"))
        && !normalized.contains("/backend-api")
    {
        normalized.push_str("/backend-api");
    }
    normalized.push('/');
    normalized
}

fn string_at(value: &Value, key: &str) -> Option<String> {
    value.get(key).and_then(Value::as_str).map(str::to_owned)
}

fn failed_snapshot(
    error: ProviderError,
    metrics: Vec<UsageMetric>,
    now: DateTime<Utc>,
) -> ProviderSnapshot {
    ProviderSnapshot {
        provider: ProviderId::Codex,
        auth_state: ProviderAuthState::Configured,
        fetch_state: ProviderFetchState::Failed,
        fetched_at_utc: Some(now),
        metrics,
        error_description: Some(error.to_string()),
        source_description: Some("Local Codex auth".to_owned()),
    }
}

fn network_error(error: reqwest::Error) -> ProviderError {
    ProviderError::Network(format!("Codex request failed: {error}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_chatgpt_urls() {
        assert_eq!(
            normalize_base_url("https://chatgpt.com"),
            "https://chatgpt.com/backend-api/"
        );
        assert_eq!(
            normalize_base_url("https://example.test/api/"),
            "https://example.test/api/"
        );
    }

    #[test]
    fn reads_base_url_without_accepting_comments() {
        assert_eq!(
            configured_base_url(
                "# chatgpt_base_url = 'https://bad.test'\nchatgpt_base_url = \"https://good.test\" # comment"
            )
            .as_deref(),
            Some("https://good.test")
        );
    }
}
