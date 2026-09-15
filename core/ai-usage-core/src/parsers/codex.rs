use std::collections::HashMap;

use chrono::{DateTime, Utc};
use serde_json::{Map, Value};

use crate::models::{MetricUnit, UsageMetric, UsageMetricKind};

use super::ParseError;

#[derive(Clone, Debug, PartialEq)]
pub struct CodexCredentials {
    pub access_token: String,
    pub refresh_token: String,
    pub id_token: Option<String>,
    pub account_id: Option<String>,
    pub last_refresh: Option<DateTime<Utc>>,
}

pub fn parse_codex_credentials(data: &[u8]) -> Result<CodexCredentials, ParseError> {
    let root: Value = serde_json::from_slice(data)?;
    if let Some(api_key) = clean_string(root.get("OPENAI_API_KEY")) {
        return Ok(CodexCredentials {
            access_token: api_key,
            refresh_token: String::new(),
            id_token: None,
            account_id: None,
            last_refresh: None,
        });
    }

    let tokens = root
        .get("tokens")
        .and_then(Value::as_object)
        .ok_or(ParseError::MissingCredentials)?;
    let access_token = clean_string(tokens.get("access_token"))
        .or_else(|| clean_string(tokens.get("accessToken")))
        .ok_or(ParseError::MissingCredentials)?;

    Ok(CodexCredentials {
        access_token,
        refresh_token: clean_string(tokens.get("refresh_token"))
            .or_else(|| clean_string(tokens.get("refreshToken")))
            .unwrap_or_default(),
        id_token: clean_string(tokens.get("id_token"))
            .or_else(|| clean_string(tokens.get("idToken"))),
        account_id: clean_string(tokens.get("account_id"))
            .or_else(|| clean_string(tokens.get("accountId"))),
        last_refresh: root
            .get("last_refresh")
            .and_then(Value::as_str)
            .and_then(|value| DateTime::parse_from_rfc3339(value).ok())
            .map(|value| value.with_timezone(&Utc)),
    })
}

pub fn parse_codex_usage(
    payload: &Value,
    now: DateTime<Utc>,
) -> Result<Vec<UsageMetric>, ParseError> {
    let root = payload.as_object().ok_or(ParseError::UnrecognizedPayload)?;
    let mut parsed = Vec::new();

    if let Some(rate_limit) = root.get("rate_limit").and_then(Value::as_object) {
        parsed.extend(rate_limit_metrics(rate_limit, now));
    }

    if let Some(balance) = root
        .get("credits")
        .and_then(Value::as_object)
        .and_then(|credits| number(credits.get("balance")))
    {
        parsed.push(UsageMetric {
            kind: UsageMetricKind::CodexCredits,
            remaining_fraction: None,
            remaining_value: Some(balance),
            total_value: None,
            unit: MetricUnit::Credits,
            reset_at_utc: None,
            last_updated_at_utc: now,
            detail_text: Some(format!("{} credits", balance.round() as i64)),
        });
    }

    let reset_credits = root
        .get("rate_limit_reset_credits")
        .or_else(|| root.get("rateLimitResetCredits"))
        .and_then(Value::as_object)
        .and_then(|credits| {
            number(
                credits
                    .get("available_count")
                    .or_else(|| credits.get("availableCount")),
            )
        });
    if let Some(available_count) = reset_credits {
        parsed.push(UsageMetric {
            kind: UsageMetricKind::CodexLimitResets,
            remaining_fraction: None,
            remaining_value: Some(available_count),
            total_value: None,
            unit: MetricUnit::Credits,
            reset_at_utc: None,
            last_updated_at_utc: now,
            detail_text: Some(format!("{} resets", available_count.round() as i64)),
        });
    }

    if parsed.is_empty() {
        return Err(ParseError::UnrecognizedPayload);
    }

    let mut by_kind: HashMap<UsageMetricKind, UsageMetric> = parsed
        .into_iter()
        .map(|metric| (metric.kind, metric))
        .collect();
    let ordered = [
        UsageMetricKind::CodexFiveHour,
        UsageMetricKind::CodexWeekly,
        UsageMetricKind::CodexCredits,
        UsageMetricKind::CodexLimitResets,
    ];

    Ok(ordered
        .into_iter()
        .filter_map(|kind| {
            by_kind.remove(&kind).or_else(|| {
                (kind != UsageMetricKind::CodexLimitResets)
                    .then(|| UsageMetric::unavailable(kind, now))
            })
        })
        .collect())
}

fn rate_limit_metrics(
    rate_limit: &Map<String, Value>,
    now: DateTime<Utc>,
) -> Vec<UsageMetric> {
    [
        ("primary_window", UsageMetricKind::CodexFiveHour),
        ("secondary_window", UsageMetricKind::CodexWeekly),
    ]
    .into_iter()
    .filter_map(|(key, fallback_kind)| {
        let window = rate_limit.get(key)?.as_object()?;
        let kind = match number(window.get("limit_window_seconds")) {
            Some(duration) if duration >= 604_800.0 => UsageMetricKind::CodexWeekly,
            Some(_) => UsageMetricKind::CodexFiveHour,
            None => fallback_kind,
        };
        rate_limit_metric(window, kind, now)
    })
    .collect()
}

fn rate_limit_metric(
    window: &Map<String, Value>,
    kind: UsageMetricKind,
    now: DateTime<Utc>,
) -> Option<UsageMetric> {
    let used_percent = number(window.get("used_percent"))?;
    let remaining_fraction = (1.0 - used_percent / 100.0).clamp(0.0, 1.0);
    let reset_at_utc =
        number(window.get("reset_at")).and_then(|value| DateTime::from_timestamp(value as i64, 0));

    Some(UsageMetric {
        kind,
        remaining_fraction: Some(remaining_fraction),
        remaining_value: Some(remaining_fraction * 100.0),
        total_value: Some(100.0),
        unit: MetricUnit::Percentage,
        reset_at_utc,
        last_updated_at_utc: now,
        detail_text: Some(format!(
            "{}% remaining",
            (remaining_fraction * 100.0).round() as i64
        )),
    })
}

fn number(value: Option<&Value>) -> Option<f64> {
    value.and_then(|value| {
        value
            .as_f64()
            .or_else(|| value.as_str().and_then(|text| text.parse().ok()))
    })
}

fn clean_string(value: Option<&Value>) -> Option<String> {
    value
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
}

#[cfg(test)]
mod tests {
    use chrono::TimeZone;
    use serde_json::json;

    use super::*;

    #[test]
    fn parses_codex_windows_credits_and_resets() {
        let now = Utc.with_ymd_and_hms(2026, 4, 15, 12, 0, 0).unwrap();
        let metrics = parse_codex_usage(
            &json!({
                "rate_limit": {
                    "primary_window": {"used_percent": 25, "limit_window_seconds": 18000, "reset_at": 1776279600},
                    "secondary_window": {"used_percent": "60", "limit_window_seconds": 604800, "reset_at": 1776729600}
                },
                "credits": {"balance": "42"},
                "rate_limit_reset_credits": {"available_count": 3}
            }),
            now,
        )
        .unwrap();

        assert_eq!(
            metrics.iter().map(|metric| metric.kind).collect::<Vec<_>>(),
            vec![
                UsageMetricKind::CodexFiveHour,
                UsageMetricKind::CodexWeekly,
                UsageMetricKind::CodexCredits,
                UsageMetricKind::CodexLimitResets,
            ]
        );
        assert_eq!(metrics[0].remaining_fraction, Some(0.75));
        assert_eq!(metrics[1].remaining_fraction, Some(0.4));
        assert_eq!(metrics[2].remaining_value, Some(42.0));
        assert_eq!(metrics[3].remaining_value, Some(3.0));
    }

    #[test]
    fn parses_codex_auth_file() {
        let credentials = parse_codex_credentials(
            br#"{"tokens":{"access_token":"access","refresh_token":"refresh","account_id":"account"},"last_refresh":"2026-04-15T12:00:00Z"}"#,
        )
        .unwrap();

        assert_eq!(credentials.access_token, "access");
        assert_eq!(credentials.refresh_token, "refresh");
        assert_eq!(credentials.account_id.as_deref(), Some("account"));
    }
}
