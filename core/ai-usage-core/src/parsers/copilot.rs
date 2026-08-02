use chrono::{DateTime, Datelike, TimeZone, Utc};
use serde_json::{Map, Value};

use crate::models::{MetricUnit, UsageMetric, UsageMetricKind};

use super::ParseError;

const REMAINING_KEYS: &[&str] = &[
    "remaining_quota",
    "remainingQuota",
    "remaining_requests",
    "remainingRequests",
    "quota_remaining",
    "remaining_included_usage",
    "remainingIncludedUsage",
    "remaining_included_quota",
    "remainingIncludedQuota",
    "remaining_included_quantity",
    "remainingIncludedQuantity",
];
const TOTAL_KEYS: &[&str] = &[
    "total_monthly_quota",
    "monthly_quota",
    "included_usage",
    "includedUsage",
    "quota",
    "total_quota",
    "included_quota",
    "includedQuota",
    "included_quantity",
    "includedQuantity",
    "userPremiumRequestEntitlement",
    "filteredUserPremiumRequestEntitlement",
];
const USED_KEYS: &[&str] = &[
    "discountQuantity",
    "discount_quantity",
    "used_quota",
    "usedQuota",
    "consumed_usage",
    "consumedUsage",
    "usage",
    "used",
    "used_quantity",
    "usedQuantity",
    "included_usage_consumed",
    "includedUsageConsumed",
    "netQuantity",
    "grossQuantity",
    "quantity",
];

pub fn parse_copilot_usage(payload: &Value, now: DateTime<Utc>) -> Result<UsageMetric, ParseError> {
    if let Some(metric) = parse_internal_payload(payload, now) {
        return Ok(metric);
    }
    if let Some(metric) = parse_billing_session_card(payload, now) {
        return Ok(metric);
    }
    if let Some(metric) = parse_usage_report(payload, now) {
        return Ok(metric);
    }

    let remaining = find_number(payload, REMAINING_KEYS);
    let total = find_number(payload, TOTAL_KEYS);
    let used = find_number(payload, USED_KEYS);
    let resolved_remaining = remaining.or_else(|| Some((total? - used?).max(0.0)));
    let resolved_total = total.or_else(|| Some(resolved_remaining? + used?));
    let remaining = resolved_remaining.ok_or(ParseError::UnrecognizedPayload)?;

    Ok(metric_from_values(
        remaining,
        resolved_total,
        next_copilot_reset(now),
        now,
    ))
}

pub fn next_copilot_reset(now: DateTime<Utc>) -> DateTime<Utc> {
    let (year, month) = if now.month() == 12 {
        (now.year() + 1, 1)
    } else {
        (now.year(), now.month() + 1)
    };
    Utc.with_ymd_and_hms(year, month, 1, 0, 0, 0)
        .single()
        .unwrap_or(now)
}

#[derive(Clone, Debug)]
struct QuotaSnapshot {
    entitlement: Option<f64>,
    remaining: Option<f64>,
    percent_remaining: Option<f64>,
}

impl QuotaSnapshot {
    fn usable(&self) -> bool {
        self.remaining.is_some() && self.percent_remaining.is_some()
    }
}

fn parse_internal_payload(payload: &Value, now: DateTime<Utc>) -> Option<UsageMetric> {
    let root = payload.as_object()?;
    let snapshots = object_at(root, "quota_snapshots", "quotaSnapshots");
    let premium = snapshots
        .and_then(|value| value.get("premium_interactions"))
        .and_then(quota_snapshot)
        .filter(QuotaSnapshot::usable);
    let chat = snapshots
        .and_then(|value| value.get("chat"))
        .and_then(quota_snapshot)
        .filter(QuotaSnapshot::usable);
    let unknown = snapshots
        .into_iter()
        .flat_map(|value| value.values())
        .filter_map(quota_snapshot)
        .find(QuotaSnapshot::usable);

    let monthly = object_at(root, "monthly_quotas", "monthlyQuotas");
    let limited = object_at(root, "limited_user_quotas", "limitedUserQuotas");
    let fallback_premium = monthly.and_then(|monthly| {
        let entitlement = monthly
            .get("completions")
            .or_else(|| monthly.get("premium_interactions"));
        let remaining = limited.and_then(|limited| {
            limited
                .get("completions")
                .or_else(|| limited.get("premium_interactions"))
        });
        quota_snapshot_from_monthly(entitlement, remaining)
    });
    let fallback_chat = monthly.and_then(|monthly| {
        quota_snapshot_from_monthly(
            monthly.get("chat"),
            limited.and_then(|limited| limited.get("chat")),
        )
    });

    let selected = premium
        .or(fallback_premium)
        .or(chat)
        .or(fallback_chat)
        .or(unknown)?;
    let remaining = selected.remaining?;
    let reset = root
        .get("quota_reset_date")
        .or_else(|| root.get("quotaResetDate"))
        .and_then(parse_reset_date)
        .unwrap_or_else(|| next_copilot_reset(now));

    Some(UsageMetric {
        kind: UsageMetricKind::CopilotMonthly,
        remaining_fraction: selected
            .percent_remaining
            .map(|value| (value / 100.0).clamp(0.0, 1.0)),
        remaining_value: Some(remaining),
        total_value: selected.entitlement,
        unit: MetricUnit::Requests,
        reset_at_utc: Some(reset),
        last_updated_at_utc: now,
        detail_text: Some(detail_text(remaining, selected.entitlement)),
    })
}

fn parse_billing_session_card(payload: &Value, now: DateTime<Utc>) -> Option<UsageMetric> {
    let total = find_number(
        payload,
        &[
            "userPremiumRequestEntitlement",
            "filteredUserPremiumRequestEntitlement",
        ],
    )?;
    if total <= 0.0 {
        return None;
    }
    let used = find_number(payload, &["discountQuantity", "discount_quantity"]).unwrap_or_default();
    Some(metric_from_values(
        (total - used).max(0.0),
        Some(total),
        next_copilot_reset(now),
        now,
    ))
}

fn parse_usage_report(payload: &Value, now: DateTime<Utc>) -> Option<UsageMetric> {
    let root = payload.as_object()?;
    if root
        .get("usageItems")
        .and_then(Value::as_array)
        .is_some_and(Vec::is_empty)
    {
        let mut metric = UsageMetric::unavailable(UsageMetricKind::CopilotMonthly, now);
        metric.unit = MetricUnit::Requests;
        metric.reset_at_utc = Some(next_copilot_reset(now));
        metric.detail_text = Some("0 requests used this month".to_owned());
        return Some(metric);
    }

    let mut items = Vec::new();
    gather_usage_items(payload, &mut items);
    let copilot_items: Vec<&Map<String, Value>> = items
        .into_iter()
        .filter(|item| {
            let product = normalized_string(item.get("product")).to_lowercase();
            let sku = normalized_string(item.get("sku")).to_lowercase();
            product.contains("copilot")
                || sku.contains("premium request")
                || sku.contains("copilot")
        })
        .collect();
    if copilot_items.is_empty() {
        return None;
    }

    let total = find_number(payload, TOTAL_KEYS).or_else(|| {
        copilot_items
            .iter()
            .filter_map(|item| find_number(&Value::Object((*item).clone()), TOTAL_KEYS))
            .max_by(f64::total_cmp)
    });
    let used: f64 = copilot_items
        .iter()
        .map(|item| {
            find_number(
                &Value::Object((*item).clone()),
                &[
                    "netQuantity",
                    "grossQuantity",
                    "quantity",
                    "used_quota",
                    "usedQuota",
                    "used_quantity",
                    "usedQuantity",
                    "consumed_usage",
                    "consumedUsage",
                ],
            )
            .unwrap_or_default()
        })
        .sum();

    let remaining = total.map(|total| (total - used).max(0.0));
    let mut metric = UsageMetric::unavailable(UsageMetricKind::CopilotMonthly, now);
    metric.unit = MetricUnit::Requests;
    metric.remaining_fraction = total
        .zip(remaining)
        .map(|(total, remaining)| (remaining / total.max(1.0)).clamp(0.0, 1.0));
    metric.remaining_value = remaining;
    metric.total_value = total;
    metric.reset_at_utc = Some(next_copilot_reset(now));
    metric.detail_text = Some(match (total, remaining) {
        (Some(total), Some(remaining)) => detail_text(remaining, Some(total)),
        _ => format!("{} requests used this month", used.round() as i64),
    });
    Some(metric)
}

fn metric_from_values(
    remaining: f64,
    total: Option<f64>,
    reset_at: DateTime<Utc>,
    now: DateTime<Utc>,
) -> UsageMetric {
    UsageMetric {
        kind: UsageMetricKind::CopilotMonthly,
        remaining_fraction: total.map(|total| (remaining / total.max(1.0)).clamp(0.0, 1.0)),
        remaining_value: Some(remaining),
        total_value: total,
        unit: MetricUnit::Requests,
        reset_at_utc: Some(reset_at),
        last_updated_at_utc: now,
        detail_text: Some(detail_text(remaining, total)),
    }
}

fn detail_text(remaining: f64, total: Option<f64>) -> String {
    match total {
        Some(total) => format!(
            "{} of {} requests left",
            remaining.round() as i64,
            total.round() as i64
        ),
        None => format!("{} requests left", remaining.round() as i64),
    }
}

fn quota_snapshot(value: &Value) -> Option<QuotaSnapshot> {
    let root = value.as_object()?;
    let entitlement = number(root.get("entitlement"));
    let remaining = number(root.get("remaining"));
    let percent_remaining = number(root.get("percent_remaining")).or_else(|| {
        let entitlement = entitlement?;
        (entitlement > 0.0).then_some(remaining? / entitlement * 100.0)
    });
    Some(QuotaSnapshot {
        entitlement,
        remaining,
        percent_remaining,
    })
}

fn quota_snapshot_from_monthly(
    entitlement: Option<&Value>,
    remaining: Option<&Value>,
) -> Option<QuotaSnapshot> {
    let entitlement = number(entitlement)?;
    let remaining = number(remaining)?;
    (entitlement > 0.0).then_some(QuotaSnapshot {
        entitlement: Some(entitlement),
        remaining: Some(remaining),
        percent_remaining: Some(remaining / entitlement * 100.0),
    })
}

fn parse_reset_date(value: &Value) -> Option<DateTime<Utc>> {
    let text = value.as_str()?;
    DateTime::parse_from_rfc3339(text)
        .ok()
        .map(|value| value.with_timezone(&Utc))
        .or_else(|| {
            chrono::NaiveDate::parse_from_str(text, "%Y-%m-%d")
                .ok()?
                .and_hms_opt(0, 0, 0)
                .map(|value| value.and_utc())
        })
}

fn object_at<'a>(
    root: &'a Map<String, Value>,
    snake_case: &str,
    camel_case: &str,
) -> Option<&'a Map<String, Value>> {
    root.get(snake_case)
        .or_else(|| root.get(camel_case))
        .and_then(Value::as_object)
}

fn gather_usage_items<'a>(value: &'a Value, result: &mut Vec<&'a Map<String, Value>>) {
    match value {
        Value::Object(root) => {
            if let Some(items) = root.get("usageItems").and_then(Value::as_array) {
                result.extend(items.iter().filter_map(Value::as_object));
            }
            for nested in root.values() {
                gather_usage_items(nested, result);
            }
        }
        Value::Array(values) => {
            for nested in values {
                gather_usage_items(nested, result);
            }
        }
        _ => {}
    }
}

fn find_number(value: &Value, keys: &[&str]) -> Option<f64> {
    match value {
        Value::Object(root) => {
            for key in keys {
                if let Some(number) = number(root.get(*key)) {
                    return Some(number);
                }
            }
            root.values().find_map(|nested| find_number(nested, keys))
        }
        Value::Array(values) => values.iter().find_map(|nested| find_number(nested, keys)),
        _ => None,
    }
}

fn number(value: Option<&Value>) -> Option<f64> {
    value.and_then(|value| {
        value
            .as_f64()
            .or_else(|| value.as_str().and_then(|text| text.parse().ok()))
    })
}

fn normalized_string(value: Option<&Value>) -> String {
    value
        .and_then(|value| match value {
            Value::String(text) => Some(text.clone()),
            Value::Number(number) => Some(number.to_string()),
            _ => None,
        })
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use chrono::TimeZone;
    use serde_json::json;

    use super::*;

    fn now() -> DateTime<Utc> {
        Utc.timestamp_opt(1_775_000_000, 0).unwrap()
    }

    #[test]
    fn parses_internal_quota_snapshot() {
        let metric = parse_copilot_usage(
            &json!({
                "quota_reset_date": "2025-02-01",
                "quota_snapshots": {
                    "premium_interactions": {"entitlement": 500, "remaining": 450, "percent_remaining": 90},
                    "chat": {"entitlement": 300, "remaining": 150, "percent_remaining": 50}
                }
            }),
            now(),
        )
        .unwrap();

        assert_eq!(metric.remaining_value, Some(450.0));
        assert_eq!(metric.total_value, Some(500.0));
        assert_eq!(metric.remaining_fraction, Some(0.9));
    }

    #[test]
    fn parses_monthly_fallback() {
        let metric = parse_copilot_usage(
            &json!({
                "monthly_quotas": {"completions": 300},
                "limited_user_quotas": {"completions": 60}
            }),
            now(),
        )
        .unwrap();

        assert_eq!(metric.remaining_value, Some(60.0));
        assert_eq!(metric.remaining_fraction, Some(0.2));
    }

    #[test]
    fn parses_billing_report() {
        let metric = parse_copilot_usage(
            &json!({"usageItems": [{
                "product": "Copilot",
                "sku": "Copilot Premium Request",
                "netQuantity": 125,
                "total_monthly_quota": 300
            }]}),
            now(),
        )
        .unwrap();

        assert_eq!(metric.remaining_value, Some(175.0));
        assert_eq!(metric.total_value, Some(300.0));
    }
}
