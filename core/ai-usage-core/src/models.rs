use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ProviderId {
    Codex,
    Claude,
    Copilot,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum UsageMetricKind {
    CodexFiveHour,
    CodexWeekly,
    CodexSparkFiveHour,
    CodexSparkWeekly,
    CodexCredits,
    CodexLimitResets,
    ClaudeFiveHour,
    ClaudeWeekly,
    CopilotMonthly,
}

impl UsageMetricKind {
    pub const fn provider(self) -> ProviderId {
        match self {
            Self::CodexFiveHour
            | Self::CodexWeekly
            | Self::CodexSparkFiveHour
            | Self::CodexSparkWeekly
            | Self::CodexCredits
            | Self::CodexLimitResets => ProviderId::Codex,
            Self::ClaudeFiveHour | Self::ClaudeWeekly => ProviderId::Claude,
            Self::CopilotMonthly => ProviderId::Copilot,
        }
    }

    pub const fn supports_ahead_notifications(self) -> bool {
        matches!(
            self,
            Self::CodexFiveHour
                | Self::CodexWeekly
                | Self::ClaudeFiveHour
                | Self::ClaudeWeekly
                | Self::CopilotMonthly
        )
    }

    pub const fn supports_behind_notifications(self) -> bool {
        matches!(
            self,
            Self::CodexWeekly | Self::ClaudeWeekly | Self::CopilotMonthly
        )
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum MetricUnit {
    Percentage,
    Requests,
    Credits,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ProviderAuthState {
    SignedOut,
    Configured,
    Authenticated,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ProviderFetchState {
    Ok,
    MissingAuth,
    Failed,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageMetric {
    pub kind: UsageMetricKind,
    pub remaining_fraction: Option<f64>,
    pub remaining_value: Option<f64>,
    pub total_value: Option<f64>,
    pub unit: MetricUnit,
    pub reset_at_utc: Option<DateTime<Utc>>,
    pub last_updated_at_utc: DateTime<Utc>,
    pub detail_text: Option<String>,
}

impl UsageMetric {
    pub fn unavailable(kind: UsageMetricKind, now: DateTime<Utc>) -> Self {
        let unit = match kind {
            UsageMetricKind::CodexCredits | UsageMetricKind::CodexLimitResets => {
                MetricUnit::Credits
            }
            UsageMetricKind::CopilotMonthly => MetricUnit::Credits,
            _ => MetricUnit::Percentage,
        };

        Self {
            kind,
            remaining_fraction: None,
            remaining_value: None,
            total_value: None,
            unit,
            reset_at_utc: None,
            last_updated_at_utc: now,
            detail_text: None,
        }
    }
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderSnapshot {
    pub provider: ProviderId,
    pub auth_state: ProviderAuthState,
    pub fetch_state: ProviderFetchState,
    pub fetched_at_utc: Option<DateTime<Utc>>,
    pub metrics: Vec<UsageMetric>,
    pub error_description: Option<String>,
    pub source_description: Option<String>,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum UsageAlertDirection {
    Ahead,
    Behind,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageAlertState {
    pub direction: UsageAlertDirection,
    pub metric_kind: UsageMetricKind,
    pub last_triggered_at_utc: DateTime<Utc>,
    pub last_extreme_delta: f64,
    pub is_armed: bool,
}
