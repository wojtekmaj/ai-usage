use std::time::Duration;

use chrono::{DateTime, Utc};
use reqwest::StatusCode;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::{
    models::{
        ProviderAuthState, ProviderFetchState, ProviderId, ProviderSnapshot, UsageMetric,
        UsageMetricKind,
    },
    parsers::{next_copilot_reset, parse_copilot_usage},
};

use super::ProviderError;

const CLIENT_ID: &str = "Iv1.b507a08c87ecfe98";
const SCOPES: &str = "read:user";
const USAGE_URL: &str = "https://api.github.com/copilot_internal/user";

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct CopilotDeviceCode {
    #[serde(rename = "deviceCode", alias = "device_code")]
    pub device_code: String,
    #[serde(rename = "userCode", alias = "user_code")]
    pub user_code: String,
    #[serde(rename = "verificationUri", alias = "verification_uri")]
    pub verification_uri: String,
    #[serde(rename = "expiresIn", alias = "expires_in")]
    pub expires_in: u64,
    pub interval: u64,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(
    tag = "status",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum CopilotPollResult {
    Pending { retry_after_seconds: u64 },
    Complete { access_token: String },
    Expired,
}

pub async fn refresh(token: Option<&str>, now: DateTime<Utc>) -> ProviderSnapshot {
    let mut base_metric = UsageMetric::unavailable(UsageMetricKind::CopilotMonthly, now);
    base_metric.reset_at_utc = Some(next_copilot_reset(now));
    let base_metrics = vec![base_metric];
    let Some(token) = token.map(str::trim).filter(|token| !token.is_empty()) else {
        return ProviderSnapshot {
            provider: ProviderId::Copilot,
            auth_state: ProviderAuthState::SignedOut,
            fetch_state: ProviderFetchState::MissingAuth,
            fetched_at_utc: None,
            metrics: base_metrics,
            error_description: None,
            source_description: Some("GitHub device-flow token".to_owned()),
        };
    };

    match fetch_usage(token, now).await {
        Ok(metric) => ProviderSnapshot {
            provider: ProviderId::Copilot,
            auth_state: ProviderAuthState::Authenticated,
            fetch_state: ProviderFetchState::Ok,
            fetched_at_utc: Some(now),
            metrics: vec![metric],
            error_description: None,
            source_description: Some("GitHub device-flow token".to_owned()),
        },
        Err(error) => ProviderSnapshot {
            provider: ProviderId::Copilot,
            auth_state: ProviderAuthState::Configured,
            fetch_state: ProviderFetchState::Failed,
            fetched_at_utc: Some(now),
            metrics: base_metrics,
            error_description: Some(error.to_string()),
            source_description: Some("GitHub device-flow token".to_owned()),
        },
    }
}

pub async fn request_copilot_device_code() -> Result<CopilotDeviceCode, ProviderError> {
    let response = reqwest::Client::new()
        .post("https://github.com/login/device/code")
        .header("Accept", "application/json")
        .form(&[("client_id", CLIENT_ID), ("scope", SCOPES)])
        .timeout(Duration::from_secs(30))
        .send()
        .await
        .map_err(network_error)?;
    if !response.status().is_success() {
        return Err(ProviderError::InvalidResponse(format!(
            "GitHub sign-in returned HTTP {}.",
            response.status().as_u16()
        )));
    }
    response.json().await.map_err(|error| {
        ProviderError::InvalidResponse(format!(
            "GitHub sign-in returned an unexpected response: {error}"
        ))
    })
}

pub async fn poll_copilot_token(
    device_code: &str,
    default_interval: u64,
) -> Result<CopilotPollResult, ProviderError> {
    let response = reqwest::Client::new()
        .post("https://github.com/login/oauth/access_token")
        .header("Accept", "application/json")
        .form(&[
            ("client_id", CLIENT_ID),
            ("device_code", device_code),
            ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"),
        ])
        .timeout(Duration::from_secs(30))
        .send()
        .await
        .map_err(network_error)?;
    let payload: Value = response.json().await.map_err(network_error)?;

    if let Some(error) = payload.get("error").and_then(Value::as_str) {
        return match error {
            "authorization_pending" => Ok(CopilotPollResult::Pending {
                retry_after_seconds: default_interval,
            }),
            "slow_down" => Ok(CopilotPollResult::Pending {
                retry_after_seconds: default_interval + 5,
            }),
            "expired_token" => Ok(CopilotPollResult::Expired),
            _ => Err(ProviderError::InvalidAuth(format!(
                "GitHub sign-in failed: {error}"
            ))),
        };
    }

    let access_token = payload
        .get("access_token")
        .and_then(Value::as_str)
        .filter(|token| !token.is_empty())
        .ok_or_else(|| {
            ProviderError::InvalidResponse(
                "GitHub sign-in returned an unexpected response.".to_owned(),
            )
        })?;
    Ok(CopilotPollResult::Complete {
        access_token: access_token.to_owned(),
    })
}

async fn fetch_usage(token: &str, now: DateTime<Utc>) -> Result<UsageMetric, ProviderError> {
    let response = reqwest::Client::new()
        .get(USAGE_URL)
        .header("Authorization", format!("token {token}"))
        .header("Accept", "application/json")
        .header("Editor-Version", "vscode/1.96.2")
        .header("Editor-Plugin-Version", "copilot-chat/0.26.7")
        .header("User-Agent", "GitHubCopilotChat/0.26.7")
        .header("X-Github-Api-Version", "2025-04-01")
        .timeout(Duration::from_secs(30))
        .send()
        .await
        .map_err(network_error)?;
    let status = response.status();
    let payload: Value = response.json().await.map_err(network_error)?;
    if matches!(status, StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN) {
        return Err(ProviderError::InvalidAuth(
            "GitHub Copilot sign-in expired. Sign in again and refresh.".to_owned(),
        ));
    }
    if !status.is_success() {
        return Err(ProviderError::InvalidResponse(format!(
            "GitHub Copilot usage API returned HTTP {}: {payload}",
            status.as_u16()
        )));
    }
    parse_copilot_usage(&payload, now)
        .map_err(|error| ProviderError::InvalidResponse(error.to_string()))
}

fn network_error(error: reqwest::Error) -> ProviderError {
    ProviderError::Network(format!("GitHub request failed: {error}"))
}
