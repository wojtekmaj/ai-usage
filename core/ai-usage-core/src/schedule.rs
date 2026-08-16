use chrono::{DateTime, Months, TimeDelta, Utc};
use serde::{Deserialize, Serialize};

use crate::models::{UsageAlertDirection, UsageAlertState, UsageMetric, UsageMetricKind};

#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum UsagePaceState {
    Ahead,
    OnTrack,
    Behind,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsagePaceAssessment {
    pub state: UsagePaceState,
    pub expected_remaining: f64,
    pub actual_remaining: f64,
    pub delta: f64,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EvaluationResult {
    pub direction: UsageAlertDirection,
    pub state: UsageAlertState,
    pub should_notify: bool,
    pub delta: f64,
    pub expected_remaining: f64,
    pub actual_remaining: f64,
}

pub fn pace_assessment(
    metric: &UsageMetric,
    now: DateTime<Utc>,
    trigger: f64,
) -> Option<UsagePaceAssessment> {
    let actual_remaining = metric.remaining_fraction?;
    let (start, end) = period_range(metric.kind, metric.reset_at_utc?, now)?;
    let duration = (end - start).num_milliseconds().max(1) as f64;
    let elapsed = ((now - start).num_milliseconds() as f64 / duration).clamp(0.0, 1.0);
    let expected_remaining = 1.0 - elapsed;
    let delta = actual_remaining - expected_remaining;
    let state = if delta <= -trigger {
        UsagePaceState::Ahead
    } else if delta >= trigger {
        UsagePaceState::Behind
    } else {
        UsagePaceState::OnTrack
    };

    Some(UsagePaceAssessment {
        state,
        expected_remaining,
        actual_remaining,
        delta,
    })
}

pub fn evaluate(
    metric: &UsageMetric,
    direction: UsageAlertDirection,
    previous_state: Option<&UsageAlertState>,
    now: DateTime<Utc>,
    trigger: f64,
    rearm_margin: f64,
) -> Option<EvaluationResult> {
    let assessment = pace_assessment(metric, now, trigger)?;
    let severity = match direction {
        UsageAlertDirection::Ahead if metric.kind.supports_ahead_notifications() => {
            -assessment.delta
        }
        UsageAlertDirection::Behind if metric.kind.supports_behind_notifications() => {
            assessment.delta
        }
        _ => return None,
    };

    if severity <= 0.0 {
        return Some(result(
            direction,
            UsageAlertState {
                direction,
                metric_kind: metric.kind,
                last_triggered_at_utc: previous_state
                    .map_or(now, |state| state.last_triggered_at_utc),
                last_extreme_delta: 0.0,
                is_armed: true,
            },
            false,
            assessment,
        ));
    }

    let matching_previous = previous_state
        .filter(|state| state.direction == direction && state.metric_kind == metric.kind);
    let mut state = matching_previous.cloned().unwrap_or(UsageAlertState {
        direction,
        metric_kind: metric.kind,
        last_triggered_at_utc: now,
        last_extreme_delta: 0.0,
        is_armed: true,
    });
    let rearm_threshold = (trigger - rearm_margin).max(0.0);

    if severity <= rearm_threshold {
        state.is_armed = true;
        state.last_extreme_delta = severity;
        return Some(result(direction, state, false, assessment));
    }

    if severity >= trigger && state.is_armed {
        state.is_armed = false;
        state.last_triggered_at_utc = now;
        state.last_extreme_delta = severity;
        return Some(result(direction, state, true, assessment));
    }

    state.last_extreme_delta = state.last_extreme_delta.max(severity);
    Some(result(direction, state, false, assessment))
}

fn result(
    direction: UsageAlertDirection,
    state: UsageAlertState,
    should_notify: bool,
    assessment: UsagePaceAssessment,
) -> EvaluationResult {
    EvaluationResult {
        direction,
        state,
        should_notify,
        delta: assessment.delta,
        expected_remaining: assessment.expected_remaining,
        actual_remaining: assessment.actual_remaining,
    }
}

fn period_range(
    kind: UsageMetricKind,
    reset_at: DateTime<Utc>,
    now: DateTime<Utc>,
) -> Option<(DateTime<Utc>, DateTime<Utc>)> {
    let duration = match kind {
        UsageMetricKind::CodexFiveHour
        | UsageMetricKind::CodexSparkFiveHour
        | UsageMetricKind::ClaudeFiveHour => TimeDelta::hours(5),
        UsageMetricKind::CodexWeekly
        | UsageMetricKind::CodexSparkWeekly
        | UsageMetricKind::ClaudeWeekly => TimeDelta::days(7),
        UsageMetricKind::CopilotMonthly => {
            let start = reset_at.checked_sub_months(Months::new(1)).unwrap_or(now);
            return Some((start, reset_at));
        }
        UsageMetricKind::CodexCredits | UsageMetricKind::CodexLimitResets => return None,
    };
    Some((reset_at - duration, reset_at))
}

#[cfg(test)]
mod tests {
    use chrono::{TimeZone, Utc};

    use crate::models::{MetricUnit, UsageAlertDirection};

    use super::*;

    fn metric(
        kind: UsageMetricKind,
        remaining: f64,
        reset_at: DateTime<Utc>,
        now: DateTime<Utc>,
    ) -> UsageMetric {
        UsageMetric {
            kind,
            remaining_fraction: Some(remaining),
            remaining_value: Some(remaining * 1_000.0),
            total_value: Some(1_000.0),
            unit: MetricUnit::Requests,
            reset_at_utc: Some(reset_at),
            last_updated_at_utc: now,
            detail_text: None,
        }
    }

    fn monthly_metric(remaining: f64, now: DateTime<Utc>) -> UsageMetric {
        metric(
            UsageMetricKind::CopilotMonthly,
            remaining,
            Utc.with_ymd_and_hms(2026, 5, 1, 0, 0, 0).unwrap(),
            now,
        )
    }

    #[test]
    fn assessment_matches_existing_thresholds() {
        let now = Utc.with_ymd_and_hms(2026, 4, 15, 12, 0, 0).unwrap();
        assert_eq!(
            pace_assessment(&monthly_metric(0.39, now), now, 0.09)
                .unwrap()
                .state,
            UsagePaceState::Ahead
        );
        assert_eq!(
            pace_assessment(&monthly_metric(0.47, now), now, 0.09)
                .unwrap()
                .state,
            UsagePaceState::OnTrack
        );
        assert_eq!(
            pace_assessment(&monthly_metric(0.62, now), now, 0.09)
                .unwrap()
                .state,
            UsagePaceState::Behind
        );
    }

    #[test]
    fn ahead_alert_requires_rearming_before_it_repeats() {
        let now = Utc.with_ymd_and_hms(2026, 4, 15, 12, 0, 0).unwrap();
        let first = evaluate(
            &monthly_metric(0.30, now),
            UsageAlertDirection::Ahead,
            None,
            now,
            0.18,
            0.10,
        )
        .unwrap();
        assert!(first.should_notify);

        let repeated = evaluate(
            &monthly_metric(0.34, now),
            UsageAlertDirection::Ahead,
            Some(&first.state),
            now,
            0.18,
            0.10,
        )
        .unwrap();
        assert!(!repeated.should_notify);
        assert!(!repeated.state.is_armed);

        let recovered = evaluate(
            &monthly_metric(0.80, now),
            UsageAlertDirection::Ahead,
            Some(&repeated.state),
            now,
            0.18,
            0.10,
        )
        .unwrap();
        assert!(recovered.state.is_armed);

        let repeated_after_rearming = evaluate(
            &monthly_metric(0.25, now),
            UsageAlertDirection::Ahead,
            Some(&recovered.state),
            now,
            0.18,
            0.10,
        )
        .unwrap();
        assert!(repeated_after_rearming.should_notify);
    }

    #[test]
    fn behind_alerts_ignore_five_hour_windows() {
        let now = Utc.with_ymd_and_hms(2026, 4, 15, 12, 0, 0).unwrap();
        let five_hour = metric(
            UsageMetricKind::CodexFiveHour,
            0.95,
            now + TimeDelta::hours(5),
            now,
        );

        assert_eq!(
            evaluate(
                &five_hour,
                UsageAlertDirection::Behind,
                None,
                now,
                0.18,
                0.10,
            ),
            None
        );
    }

    #[test]
    fn behind_alert_does_not_repeat_when_only_the_reset_time_wobbles() {
        let now = Utc.with_ymd_and_hms(2026, 4, 15, 10, 20, 0).unwrap();
        let reset_at = Utc.with_ymd_and_hms(2026, 4, 19, 10, 19, 19).unwrap();
        let first = evaluate(
            &metric(UsageMetricKind::CodexWeekly, 0.79, reset_at, now),
            UsageAlertDirection::Behind,
            None,
            now,
            0.18,
            0.10,
        )
        .unwrap();
        assert!(first.should_notify);

        let five_minutes_later = now + TimeDelta::minutes(5);
        let repeated = evaluate(
            &metric(
                UsageMetricKind::CodexWeekly,
                0.79,
                reset_at + TimeDelta::seconds(1),
                five_minutes_later,
            ),
            UsageAlertDirection::Behind,
            Some(&first.state),
            five_minutes_later,
            0.18,
            0.10,
        )
        .unwrap();

        assert!(!repeated.should_notify);
        assert!(!repeated.state.is_armed);
    }
}
