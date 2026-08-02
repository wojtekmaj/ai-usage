use chrono::{DateTime, TimeZone, Utc};
use serde::Deserialize;

use crate::models::{MetricUnit, UsageMetric, UsageMetricKind};

use super::ParseError;

#[derive(Clone, Debug, PartialEq)]
pub struct ClaudeCredentials {
    pub access_token: String,
    pub expires_at: Option<DateTime<Utc>>,
    pub scopes: Vec<String>,
    pub rate_limit_tier: Option<String>,
}

impl ClaudeCredentials {
    pub fn has_usage_scope(&self) -> bool {
        self.scopes.iter().any(|scope| scope == "user:profile")
    }

    pub fn is_expired_at(&self, now: DateTime<Utc>) -> bool {
        self.expires_at.is_some_and(|expires_at| now >= expires_at)
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ClaudeCredentialsRoot {
    claude_ai_oauth: Option<ClaudeOAuth>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ClaudeOAuth {
    access_token: Option<String>,
    expires_at: Option<f64>,
    scopes: Option<Vec<String>>,
    rate_limit_tier: Option<String>,
}

pub fn parse_claude_credentials(data: &[u8]) -> Result<ClaudeCredentials, ParseError> {
    let root: ClaudeCredentialsRoot = serde_json::from_slice(data)?;
    let oauth = root.claude_ai_oauth.ok_or(ParseError::MissingCredentials)?;
    let access_token = oauth.access_token.unwrap_or_default().trim().to_owned();
    if access_token.is_empty() {
        return Err(ParseError::MissingCredentials);
    }

    Ok(ClaudeCredentials {
        access_token,
        expires_at: oauth
            .expires_at
            .and_then(|milliseconds| Utc.timestamp_millis_opt(milliseconds as i64).single()),
        scopes: oauth.scopes.unwrap_or_default(),
        rate_limit_tier: oauth.rate_limit_tier,
    })
}

#[derive(Deserialize)]
struct ClaudeUsageResponse {
    five_hour: Option<ClaudeUsageWindow>,
    seven_day: Option<ClaudeUsageWindow>,
    seven_day_oauth_apps: Option<ClaudeUsageWindow>,
}

#[derive(Deserialize)]
struct ClaudeUsageWindow {
    utilization: Option<f64>,
    resets_at: Option<String>,
}

pub fn parse_claude_usage(data: &[u8], now: DateTime<Utc>) -> Result<Vec<UsageMetric>, ParseError> {
    let response: ClaudeUsageResponse = serde_json::from_slice(data)?;
    let weekly = response.seven_day.or(response.seven_day_oauth_apps);

    Ok(vec![
        metric(UsageMetricKind::ClaudeFiveHour, response.five_hour, now),
        metric(UsageMetricKind::ClaudeWeekly, weekly, now),
    ])
}

fn metric(
    kind: UsageMetricKind,
    window: Option<ClaudeUsageWindow>,
    now: DateTime<Utc>,
) -> UsageMetric {
    let utilization = window
        .as_ref()
        .and_then(|window| window.utilization)
        .map(|value| (value / 100.0).clamp(0.0, 1.0));
    let remaining_fraction = utilization.map(|value| (1.0 - value).clamp(0.0, 1.0));

    UsageMetric {
        kind,
        remaining_fraction,
        remaining_value: remaining_fraction,
        total_value: utilization.map(|_| 1.0),
        unit: MetricUnit::Percentage,
        reset_at_utc: window
            .and_then(|window| window.resets_at)
            .and_then(|value| DateTime::parse_from_rfc3339(&value).ok())
            .map(|value| value.with_timezone(&Utc)),
        last_updated_at_utc: now,
        detail_text: remaining_fraction
            .map(|remaining| format!("{}% remaining", (remaining * 100.0).round() as i64)),
    }
}

#[cfg(test)]
mod tests {
    use chrono::DateTime;

    use super::*;

    #[test]
    fn parses_usage_windows() {
        let now = DateTime::parse_from_rfc3339("2026-04-15T12:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        let metrics = parse_claude_usage(
            br#"{
                "five_hour":{"utilization":25,"resets_at":"2026-04-15T15:00:00Z"},
                "seven_day":{"utilization":60,"resets_at":"2026-04-20T00:00:00.000Z"}
            }"#,
            now,
        )
        .unwrap();

        assert_eq!(metrics[0].remaining_fraction, Some(0.75));
        assert_eq!(metrics[1].remaining_fraction, Some(0.4));
        assert_eq!(metrics[0].kind, UsageMetricKind::ClaudeFiveHour);
    }

    #[test]
    fn parses_local_credentials() {
        let credentials = parse_claude_credentials(
            br#"{"claudeAiOauth":{"accessToken":" token ","expiresAt":1776056400000,"scopes":["user:profile"]}}"#,
        )
        .unwrap();

        assert_eq!(credentials.access_token, "token");
        assert!(credentials.has_usage_scope());
    }
}
