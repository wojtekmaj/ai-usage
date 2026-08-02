use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json, to_value};

use crate::{
    models::{ProviderId, UsageAlertDirection, UsageAlertState, UsageMetric},
    providers::{
        current_auth_state, poll_copilot_token, refresh_provider, request_copilot_device_code,
    },
    schedule::{evaluate, pace_assessment},
};

#[derive(Debug, Deserialize)]
#[serde(
    tag = "command",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum CoreRequest {
    Health,
    AuthState {
        provider: ProviderId,
        #[serde(default)]
        copilot_token_present: bool,
        claude_credentials_json: Option<String>,
    },
    Refresh {
        provider: ProviderId,
        copilot_token: Option<String>,
        claude_credentials_json: Option<String>,
        now: Option<DateTime<Utc>>,
    },
    RequestCopilotDeviceCode,
    PollCopilotToken {
        device_code: String,
        default_interval: u64,
    },
    PaceAssessment {
        metric: UsageMetric,
        now: DateTime<Utc>,
        #[serde(default = "default_pace_trigger")]
        trigger: f64,
    },
    EvaluateSchedule {
        metric: UsageMetric,
        direction: UsageAlertDirection,
        previous_state: Option<UsageAlertState>,
        now: DateTime<Utc>,
        #[serde(default = "default_alert_trigger")]
        trigger: f64,
        #[serde(default = "default_rearm_margin")]
        rearm_margin: f64,
    },
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CoreResponse {
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<CoreError>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CoreError {
    pub code: String,
    pub message: String,
}

impl CoreResponse {
    pub fn success<T: Serialize>(data: T) -> Self {
        match to_value(data) {
            Ok(data) => Self {
                ok: true,
                data: Some(data),
                error: None,
            },
            Err(error) => Self::failure("serializationFailed", error.to_string()),
        }
    }

    pub fn failure(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            ok: false,
            data: None,
            error: Some(CoreError {
                code: code.into(),
                message: message.into(),
            }),
        }
    }
}

pub async fn handle(request: CoreRequest) -> CoreResponse {
    match request {
        CoreRequest::Health => CoreResponse::success(json!({
            "protocolVersion": 1,
            "coreVersion": env!("CARGO_PKG_VERSION")
        })),
        CoreRequest::AuthState {
            provider,
            copilot_token_present,
            claude_credentials_json,
        } => CoreResponse::success(
            current_auth_state(
                provider,
                copilot_token_present,
                claude_credentials_json.as_deref(),
            )
            .await,
        ),
        CoreRequest::Refresh {
            provider,
            copilot_token,
            claude_credentials_json,
            now,
        } => CoreResponse::success(
            refresh_provider(
                provider,
                copilot_token.as_deref(),
                claude_credentials_json.as_deref(),
                now.unwrap_or_else(Utc::now),
            )
            .await,
        ),
        CoreRequest::RequestCopilotDeviceCode => match request_copilot_device_code().await {
            Ok(response) => CoreResponse::success(response),
            Err(error) => CoreResponse::failure("githubDeviceFlowFailed", error.to_string()),
        },
        CoreRequest::PollCopilotToken {
            device_code,
            default_interval,
        } => match poll_copilot_token(&device_code, default_interval).await {
            Ok(response) => CoreResponse::success(response),
            Err(error) => CoreResponse::failure("githubDeviceFlowFailed", error.to_string()),
        },
        CoreRequest::PaceAssessment {
            metric,
            now,
            trigger,
        } => CoreResponse::success(pace_assessment(&metric, now, trigger)),
        CoreRequest::EvaluateSchedule {
            metric,
            direction,
            previous_state,
            now,
            trigger,
            rearm_margin,
        } => CoreResponse::success(evaluate(
            &metric,
            direction,
            previous_state.as_ref(),
            now,
            trigger,
            rearm_margin,
        )),
    }
}

const fn default_pace_trigger() -> f64 {
    0.09
}

const fn default_alert_trigger() -> f64 {
    0.18
}

const fn default_rearm_margin() -> f64 {
    0.10
}
