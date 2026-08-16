use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Value, to_value};

use crate::{
    models::{UsageAlertDirection, UsageAlertState, UsageMetric},
    providers::{poll_copilot_token, preheat_codex, refresh_all, request_copilot_device_code},
    schedule::{EvaluationResult, evaluate},
};

pub const PROTOCOL_VERSION: u32 = 1;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CoreRequest {
    pub protocol_version: u32,
    #[serde(flatten)]
    pub command: CoreCommand,
}

#[derive(Debug, Deserialize)]
#[serde(
    tag = "command",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum CoreCommand {
    Refresh {
        copilot_token: Option<String>,
        claude_credentials_json: Option<String>,
        now: Option<DateTime<Utc>>,
    },
    RequestCopilotDeviceCode,
    PollCopilotToken {
        device_code: String,
        default_interval: u64,
    },
    PreheatCodex,
    EvaluateSchedules {
        evaluations: Vec<ScheduleEvaluation>,
        now: DateTime<Utc>,
        #[serde(default = "default_alert_trigger")]
        trigger: f64,
        #[serde(default = "default_rearm_margin")]
        rearm_margin: f64,
    },
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ScheduleEvaluation {
    pub metric: UsageMetric,
    pub direction: UsageAlertDirection,
    pub previous_state: Option<UsageAlertState>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CoreResponse {
    pub protocol_version: u32,
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
                protocol_version: PROTOCOL_VERSION,
                ok: true,
                data: Some(data),
                error: None,
            },
            Err(error) => Self::failure("serializationFailed", error.to_string()),
        }
    }

    pub fn failure(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            protocol_version: PROTOCOL_VERSION,
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
    if request.protocol_version != PROTOCOL_VERSION {
        return CoreResponse::failure(
            "unsupportedProtocolVersion",
            format!(
                "Unsupported protocol version {}. Expected {PROTOCOL_VERSION}.",
                request.protocol_version
            ),
        );
    }

    match request.command {
        CoreCommand::Refresh {
            copilot_token,
            claude_credentials_json,
            now,
        } => CoreResponse::success(
            refresh_all(
                copilot_token.as_deref(),
                claude_credentials_json.as_deref(),
                now.unwrap_or_else(Utc::now),
            )
            .await,
        ),
        CoreCommand::RequestCopilotDeviceCode => match request_copilot_device_code().await {
            Ok(response) => CoreResponse::success(response),
            Err(error) => CoreResponse::failure("githubDeviceFlowFailed", error.to_string()),
        },
        CoreCommand::PollCopilotToken {
            device_code,
            default_interval,
        } => match poll_copilot_token(&device_code, default_interval).await {
            Ok(response) => CoreResponse::success(response),
            Err(error) => CoreResponse::failure("githubDeviceFlowFailed", error.to_string()),
        },
        CoreCommand::PreheatCodex => match preheat_codex().await {
            Ok(()) => CoreResponse::success(true),
            Err(error) => CoreResponse::failure("codexPreheatFailed", error.to_string()),
        },
        CoreCommand::EvaluateSchedules {
            evaluations,
            now,
            trigger,
            rearm_margin,
        } => CoreResponse::success(
            evaluations
                .iter()
                .map(|evaluation| {
                    evaluate(
                        &evaluation.metric,
                        evaluation.direction,
                        evaluation.previous_state.as_ref(),
                        now,
                        trigger,
                        rearm_margin,
                    )
                })
                .collect::<Vec<Option<EvaluationResult>>>(),
        ),
    }
}

const fn default_alert_trigger() -> f64 {
    0.18
}

const fn default_rearm_margin() -> f64 {
    0.10
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn request_requires_an_explicit_protocol_version() {
        let error = serde_json::from_value::<CoreRequest>(json!({
            "command": "preheatCodex"
        }))
        .unwrap_err();

        assert!(error.to_string().contains("protocolVersion"));
    }

    #[tokio::test]
    async fn unsupported_protocol_versions_return_a_structured_error() {
        let response = handle(CoreRequest {
            protocol_version: PROTOCOL_VERSION + 1,
            command: CoreCommand::PreheatCodex,
        })
        .await;

        assert!(!response.ok);
        assert_eq!(response.protocol_version, PROTOCOL_VERSION);
        assert_eq!(
            response.error.as_ref().map(|error| error.code.as_str()),
            Some("unsupportedProtocolVersion")
        );
    }
}
