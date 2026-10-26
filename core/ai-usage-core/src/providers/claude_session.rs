use std::{
    process::{Command, Stdio},
    time::Duration,
};

use base64::{
    Engine,
    engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD},
};
use chrono::{DateTime, TimeDelta, Utc};
use reqwest::{StatusCode, Url};
use serde::Serialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpListener,
};

use crate::{
    models::{ProviderAuthState, ProviderFetchState, ProviderId, ProviderSnapshot},
    parsers::parse_claude_credentials,
};

use super::{ProviderError, claude};

const CLIENT_ID: &str = "9d1c250a-e61b-44d9-88ed-5944d1962f5e";
const TOKEN_URL: &str = "https://platform.claude.com/v1/oauth/token";
const USAGE_URL: &str = "https://api.anthropic.com/api/oauth/usage";
const SIGN_IN_TIMEOUT: Duration = Duration::from_secs(300);

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClaudeSessionResult {
    pub credentials_json: String,
    pub snapshot: ProviderSnapshot,
}

struct TokenFailure {
    error: ProviderError,
    retry_after: i64,
}

pub async fn sign_in(callback_message: Option<&str>) -> Result<String, ProviderError> {
    let listener = TcpListener::bind("127.0.0.1:0").await.map_err(|_| {
        ProviderError::CredentialAccess("Could not start the Claude sign-in callback.".into())
    })?;
    let port = listener
        .local_addr()
        .map_err(|_| {
            ProviderError::CredentialAccess(
                "Could not read the Claude sign-in callback address.".into(),
            )
        })?
        .port();
    let redirect = format!("http://localhost:{port}/callback");
    let verifier = random_string()?;
    let state = random_string()?;
    let authorize = authorization_url(&redirect, &verifier, &state);
    open_browser(authorize.as_str())?;

    let callback_message =
        callback_message.unwrap_or("You can close this tab and return to AI Usage.");
    let code = tokio::time::timeout(
        SIGN_IN_TIMEOUT,
        receive_code(&listener, &state, callback_message),
    )
    .await
    .map_err(|_| ProviderError::InvalidAuth("Claude sign-in timed out.".into()))??;
    let body = json!({
        "grant_type": "authorization_code",
        "code": code,
        "state": state,
        "client_id": CLIENT_ID,
        "redirect_uri": redirect,
        "code_verifier": verifier,
    });
    let token = request_token(&body, TOKEN_URL)
        .await
        .map_err(|failure| failure.error)?;
    let mut root = json!({"claudeAiOauth": {"scopes": ["user:profile"]}});
    apply_token(&mut root, token, Utc::now())?;
    let credentials = parse_claude_credentials(root.to_string().as_bytes()).map_err(|_| {
        ProviderError::InvalidAuth("Claude returned incomplete credentials.".into())
    })?;
    if !credentials.has_usage_scope() || credentials.refresh_token.is_none() {
        return Err(ProviderError::InvalidAuth(
            "Claude did not grant renewable usage access.".into(),
        ));
    }

    Ok(root.to_string())
}

fn random_string() -> Result<String, ProviderError> {
    let mut bytes = [0u8; 32];
    getrandom::fill(&mut bytes).map_err(|_| {
        ProviderError::CredentialAccess("Could not generate secure Claude sign-in state.".into())
    })?;

    Ok(URL_SAFE_NO_PAD.encode(bytes))
}

fn authorization_url(redirect: &str, verifier: &str, state: &str) -> Url {
    let challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()));
    let mut url = Url::parse("https://claude.com/cai/oauth/authorize").unwrap();
    url.query_pairs_mut().extend_pairs([
        ("code", "true"),
        ("client_id", CLIENT_ID),
        ("response_type", "code"),
        ("redirect_uri", redirect),
        ("scope", "user:profile"),
        ("code_challenge", challenge.as_str()),
        ("code_challenge_method", "S256"),
        ("state", state),
    ]);

    url
}

async fn receive_code(
    listener: &TcpListener,
    state: &str,
    callback_message: &str,
) -> Result<String, ProviderError> {
    loop {
        let (mut stream, _) = listener
            .accept()
            .await
            .map_err(|_| ProviderError::Network("Claude sign-in callback failed.".into()))?;
        let mut request = Vec::new();
        let read = tokio::time::timeout(Duration::from_secs(5), async {
            let mut buffer = [0u8; 1024];
            while request.len() < 8192 {
                let count = stream.read(&mut buffer).await?;
                if count == 0 {
                    break;
                }
                request.extend_from_slice(&buffer[..count]);
                if request.windows(4).any(|window| window == b"\r\n\r\n") {
                    break;
                }
            }

            Ok::<(), std::io::Error>(())
        })
        .await;
        if !matches!(read, Ok(Ok(()))) {
            continue;
        }

        let result = callback_code(&request, state);
        let status = if result.is_some() {
            "200 OK"
        } else {
            "400 Bad Request"
        };
        let message = callback_message
            .replace('&', "&amp;")
            .replace('<', "&lt;")
            .replace('>', "&gt;");
        let script = "history.replaceState(null, '', '/callback');";
        let script_hash = STANDARD.encode(Sha256::digest(script.as_bytes()));
        let body = format!(
            "<!doctype html><html><head><meta charset=utf-8><meta name=viewport content=\"width=device-width, initial-scale=1\"><meta name=color-scheme content=\"light dark\"><title>AI Usage</title><style>body{{font-family:system-ui,sans-serif;max-width:36rem;margin:15vh auto;padding:0 1.5rem;line-height:1.5}}</style></head><body><h1>AI Usage</h1><p>{message}</p><script>{script}</script></body></html>"
        );
        let response = format!(
            "HTTP/1.1 {status}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; script-src 'sha256-{script_hash}'\r\n\r\n{body}",
            body.len()
        );
        let _ = tokio::time::timeout(
            Duration::from_secs(2),
            stream.write_all(response.as_bytes()),
        )
        .await;
        if let Some(result) = result {
            return result;
        }
    }
}

fn callback_code(request: &[u8], state: &str) -> Option<Result<String, ProviderError>> {
    let request = std::str::from_utf8(request).ok()?;
    let line = request.lines().next()?;
    let target = line.strip_prefix("GET ")?.strip_suffix(" HTTP/1.1")?;
    if !target.starts_with("/callback?") {
        return None;
    }

    let url = Url::parse(&format!("http://localhost{target}")).ok()?;
    let pairs = url.query_pairs().collect::<Vec<_>>();
    let states = pairs
        .iter()
        .filter(|pair| pair.0 == "state")
        .collect::<Vec<_>>();
    if states.len() != 1 || states[0].1 != state {
        return None;
    }

    if pairs.iter().any(|pair| pair.0 == "error") {
        return Some(Err(ProviderError::InvalidAuth(
            "Claude sign-in was declined.".into(),
        )));
    }

    let codes = pairs
        .iter()
        .filter(|pair| pair.0 == "code")
        .collect::<Vec<_>>();
    if codes.len() != 1 || codes[0].1.is_empty() {
        return None;
    }

    Some(Ok(codes[0].1.to_string()))
}

fn open_browser(url: &str) -> Result<(), ProviderError> {
    #[cfg(target_os = "macos")]
    let status = Command::new("/usr/bin/open")
        .arg(url)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    #[cfg(target_os = "windows")]
    let status = {
        use std::os::windows::process::CommandExt;
        let system = std::env::var_os("SystemRoot").unwrap_or_else(|| "C:\\Windows".into());
        Command::new(std::path::PathBuf::from(system).join("System32/rundll32.exe"))
            .args(["url.dll,FileProtocolHandler", url])
            .creation_flags(0x08000000)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
    };
    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    let status = Command::new("xdg-open")
        .arg(url)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    if !status.is_ok_and(|status| status.success()) {
        return Err(ProviderError::CredentialAccess(
            "Could not open the browser for Claude sign-in.".into(),
        ));
    }

    Ok(())
}

pub async fn refresh_session(credentials_json: &str, now: DateTime<Utc>) -> ClaudeSessionResult {
    refresh_session_at(credentials_json, now, TOKEN_URL, USAGE_URL).await
}

async fn refresh_session_at(
    credentials_json: &str,
    now: DateTime<Utc>,
    token_url: &str,
    usage_url: &str,
) -> ClaudeSessionResult {
    let mut root = serde_json::from_str::<Value>(credentials_json).unwrap_or(Value::Null);
    let credentials = match parse_claude_credentials(credentials_json.as_bytes()) {
        Ok(credentials) => credentials,
        Err(_) => {
            return failed_session(
                root,
                ProviderError::InvalidAuth("Claude needs you to sign in.".into()),
                now,
            );
        }
    };
    if !credentials.has_usage_scope() {
        return failed_session(
            root,
            ProviderError::InvalidAuth(
                "Claude needs you to sign in again to access usage data.".into(),
            ),
            now,
        );
    }
    if root["aiUsageRefresh"]["rejected"].as_bool() == Some(true) {
        return failed_session(
            root,
            ProviderError::InvalidAuth("Claude needs you to sign in again.".into()),
            now,
        );
    }
    if root["aiUsageRefresh"]["retryAt"]
        .as_i64()
        .is_some_and(|retry_at| now.timestamp() < retry_at)
    {
        return failed_session(
            root,
            ProviderError::Network(
                "Claude is temporarily unavailable. Usage will retry automatically.".into(),
            ),
            now,
        );
    }

    let needs_refresh = credentials
        .expires_at
        .is_none_or(|expires_at| expires_at <= now + TimeDelta::minutes(5));
    if needs_refresh {
        let renewal = renew(&mut root, token_url, now).await;
        if let Err(failure) = renewal {
            return record_failure(root, failure, now);
        }
    }

    let mut usage = claude::fetch_usage(
        root["claudeAiOauth"]["accessToken"].as_str().unwrap(),
        now,
        usage_url,
    )
    .await;
    if !needs_refresh && matches!(usage, Err(ProviderError::InvalidAuth(_))) {
        let renewal = renew(&mut root, token_url, now).await;
        if let Err(failure) = renewal {
            return record_failure(root, failure, now);
        }
        usage = claude::fetch_usage(
            root["claudeAiOauth"]["accessToken"].as_str().unwrap(),
            now,
            usage_url,
        )
        .await;
    }
    let metrics = match usage {
        Ok(metrics) => metrics,
        Err(error) => {
            let retry_after = match error {
                ProviderError::RateLimited(seconds) => seconds,
                _ => 60,
            };

            return record_failure(root, TokenFailure { error, retry_after }, now);
        }
    };
    let snapshot = ProviderSnapshot {
        provider: ProviderId::Claude,
        auth_state: ProviderAuthState::Authenticated,
        fetch_state: ProviderFetchState::Ok,
        fetched_at_utc: Some(now),
        metrics,
        error_description: None,
        source_description: Some("AI Usage Claude connection".into()),
    };
    root.as_object_mut().unwrap().remove("aiUsageRefresh");

    ClaudeSessionResult {
        credentials_json: root.to_string(),
        snapshot,
    }
}

async fn renew(root: &mut Value, token_url: &str, now: DateTime<Utc>) -> Result<(), TokenFailure> {
    let refresh_token = root["claudeAiOauth"]["refreshToken"]
        .as_str()
        .filter(|token| !token.is_empty())
        .ok_or_else(|| TokenFailure {
            error: ProviderError::InvalidAuth("Claude needs you to sign in again.".into()),
            retry_after: 0,
        })?;
    let token = request_token(
        &json!({
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
            "client_id": CLIENT_ID,
        }),
        token_url,
    )
    .await?;
    apply_token(root, token, now).map_err(|error| TokenFailure {
        error,
        retry_after: 60,
    })?;
    root.as_object_mut().unwrap().remove("aiUsageRefresh");

    Ok(())
}

async fn request_token(body: &Value, token_url: &str) -> Result<Value, TokenFailure> {
    let response = reqwest::Client::new()
        .post(token_url)
        .header("Accept", "application/json")
        .header("User-Agent", "AI-Usage")
        .json(body)
        .timeout(Duration::from_secs(20))
        .send()
        .await
        .map_err(|_| TokenFailure {
            error: ProviderError::Network(
                "Claude session renewal could not connect. Usage will retry automatically.".into(),
            ),
            retry_after: 60,
        })?;
    let status = response.status();
    let retry_after = response
        .headers()
        .get("Retry-After")
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.parse::<i64>().ok())
        .unwrap_or(300)
        .clamp(1, 86400);
    if status == StatusCode::TOO_MANY_REQUESTS || status.is_server_error() {
        return Err(TokenFailure {
            error: ProviderError::Network(format!(
                "Claude session renewal returned HTTP {}. Usage will retry automatically.",
                status.as_u16()
            )),
            retry_after,
        });
    }

    let token = response.json::<Value>().await.map_err(|_| TokenFailure {
        error: ProviderError::InvalidResponse("Claude returned an invalid token response.".into()),
        retry_after: 60,
    })?;
    if (status == StatusCode::BAD_REQUEST || status == StatusCode::UNAUTHORIZED)
        && token["error"].as_str() == Some("invalid_grant")
    {
        return Err(TokenFailure {
            error: ProviderError::InvalidAuth("Claude needs you to sign in again.".into()),
            retry_after: 0,
        });
    }
    if !status.is_success() {
        return Err(TokenFailure {
            error: ProviderError::Network(format!(
                "Claude session renewal returned HTTP {}. Usage will retry automatically.",
                status.as_u16()
            )),
            retry_after,
        });
    }

    Ok(token)
}

fn apply_token(root: &mut Value, token: Value, now: DateTime<Utc>) -> Result<(), ProviderError> {
    let access = token["access_token"]
        .as_str()
        .filter(|token| !token.is_empty());
    let lifetime = token["expires_in"]
        .as_i64()
        .filter(|seconds| *seconds > 0 && *seconds <= 31_536_000);
    let (Some(access), Some(lifetime)) = (access, lifetime) else {
        return Err(ProviderError::InvalidResponse(
            "Claude returned incomplete session credentials.".into(),
        ));
    };
    let oauth = &mut root["claudeAiOauth"];
    oauth["accessToken"] = json!(access);
    oauth["expiresAt"] = json!((now + TimeDelta::seconds(lifetime)).timestamp_millis());
    if let Some(refresh) = token["refresh_token"]
        .as_str()
        .filter(|token| !token.is_empty())
    {
        oauth["refreshToken"] = json!(refresh);
    }
    if let Some(scope) = token["scope"].as_str() {
        oauth["scopes"] = json!(scope.split_whitespace().collect::<Vec<_>>());
    }

    Ok(())
}

fn record_failure(
    mut root: Value,
    failure: TokenFailure,
    now: DateTime<Utc>,
) -> ClaudeSessionResult {
    root["aiUsageRefresh"] = json!({
        "rejected": matches!(failure.error, ProviderError::InvalidAuth(_)),
        "retryAt": now.timestamp() + failure.retry_after,
    });

    failed_session(root, failure.error, now)
}

fn failed_session(root: Value, error: ProviderError, now: DateTime<Utc>) -> ClaudeSessionResult {
    let mut snapshot = claude::failed_snapshot(error, vec![], now);
    snapshot.source_description = Some("AI Usage Claude connection".into());

    ClaudeSessionResult {
        credentials_json: root.to_string(),
        snapshot,
    }
}

#[cfg(test)]
mod tests {
    use std::{
        io::{BufRead, BufReader, Read, Write},
        net::TcpListener as TestListener,
        thread::{self, JoinHandle},
        time::Instant,
    };

    use crate::models::ProviderFetchState;

    use super::*;

    const USAGE: &str = r#"{"five_hour":{"utilization":25},"seven_day":{"utilization":40}}"#;
    const TOKEN: &str =
        r#"{"access_token":"renewed-access","refresh_token":"rotated-refresh","expires_in":28800}"#;

    fn credentials(now: DateTime<Utc>, expired: bool) -> String {
        json!({"claudeAiOauth": {
            "accessToken": "original-access",
            "refreshToken": "original-refresh",
            "expiresAt": (now + TimeDelta::hours(if expired { -1 } else { 1 })).timestamp_millis(),
            "scopes": ["user:profile"],
            "rateLimitTier": "max"
        }})
        .to_string()
    }

    #[tokio::test]
    async fn fetches_usage_without_renewing_a_valid_session() {
        let now = Utc::now();
        let original = credentials(now, false);
        let (url, server) = serve_responses(vec![("GET /usage ", "200 OK", USAGE)]);

        let result = refresh_session_at(
            &original,
            now,
            &format!("{url}token"),
            &format!("{url}usage"),
        )
        .await;

        assert_eq!(result.snapshot.fetch_state, ProviderFetchState::Ok);
        assert_eq!(result.snapshot.metrics[0].remaining_fraction, Some(0.75));
        assert_eq!(
            serde_json::from_str::<Value>(&result.credentials_json).unwrap(),
            serde_json::from_str::<Value>(&original).unwrap()
        );
        server.join().unwrap();
    }

    #[tokio::test]
    async fn renews_an_expired_session_and_returns_rotated_credentials_even_when_usage_fails() {
        let now = Utc::now();
        let (url, server) = serve_responses(vec![
            ("POST /token ", "200 OK", TOKEN),
            ("GET /usage ", "503 Service Unavailable", "unavailable"),
        ]);

        let result = refresh_session_at(
            &credentials(now, true),
            now,
            &format!("{url}token"),
            &format!("{url}usage"),
        )
        .await;

        let saved = parse_claude_credentials(result.credentials_json.as_bytes()).unwrap();
        assert_eq!(saved.access_token, "renewed-access");
        assert_eq!(saved.refresh_token.as_deref(), Some("rotated-refresh"));
        assert_eq!(saved.rate_limit_tier.as_deref(), Some("max"));
        assert_eq!(saved.scopes, vec!["user:profile"]);
        assert_eq!(result.snapshot.auth_state, ProviderAuthState::Configured);
        assert_eq!(result.snapshot.fetch_state, ProviderFetchState::Failed);
        let requests = server.join().unwrap();
        assert!(requests[1].contains("Bearer renewed-access"));
    }

    #[tokio::test]
    async fn renews_early_rejected_tokens_and_retries_usage_once() {
        let now = Utc::now();
        let (url, server) = serve_responses(vec![
            ("GET /usage ", "401 Unauthorized", "expired"),
            ("POST /token ", "200 OK", TOKEN),
            ("GET /usage ", "200 OK", USAGE),
        ]);

        let result = refresh_session_at(
            &credentials(now, false),
            now,
            &format!("{url}token"),
            &format!("{url}usage"),
        )
        .await;

        assert_eq!(result.snapshot.fetch_state, ProviderFetchState::Ok);
        let requests = server.join().unwrap();
        let body: Value =
            serde_json::from_str(requests[1].split("\r\n\r\n").nth(1).unwrap()).unwrap();
        assert_eq!(body["refresh_token"], "original-refresh");
        assert_eq!(body["grant_type"], "refresh_token");
        assert!(requests[2].contains("Bearer renewed-access"));
    }

    #[tokio::test]
    async fn persists_rate_limit_backoff_without_requiring_sign_in() {
        let now = Utc::now();
        let (url, server) = serve_responses(vec![(
            "POST /token ",
            "429 Too Many Requests\r\nRetry-After: 1200",
            "<html>Try later</html>",
        )]);

        let result = refresh_session_at(
            &credentials(now, true),
            now,
            &format!("{url}token"),
            &format!("{url}usage"),
        )
        .await;
        let saved: Value = serde_json::from_str(&result.credentials_json).unwrap();

        assert_eq!(saved["aiUsageRefresh"]["retryAt"], now.timestamp() + 1200);
        assert_eq!(result.snapshot.auth_state, ProviderAuthState::Configured);
        server.join().unwrap();

        let retry = refresh_session_at(
            &result.credentials_json,
            now + TimeDelta::minutes(10),
            "http://127.0.0.1:1/token",
            "http://127.0.0.1:1/usage",
        )
        .await;

        assert_eq!(retry.snapshot.auth_state, ProviderAuthState::Configured);
        assert_eq!(retry.credentials_json, result.credentials_json);
    }

    #[tokio::test]
    async fn stops_retrying_a_revoked_refresh_token_across_restarts() {
        let now = Utc::now();
        let (url, server) = serve_responses(vec![(
            "POST /token ",
            "400 Bad Request",
            r#"{"error":"invalid_grant"}"#,
        )]);

        let result = refresh_session_at(
            &credentials(now, true),
            now,
            &format!("{url}token"),
            &format!("{url}usage"),
        )
        .await;

        assert_eq!(result.snapshot.auth_state, ProviderAuthState::SignedOut);
        server.join().unwrap();

        let retry = refresh_session_at(
            &result.credentials_json,
            now + TimeDelta::days(1),
            "http://127.0.0.1:1/token",
            "http://127.0.0.1:1/usage",
        )
        .await;

        assert_eq!(retry.snapshot.auth_state, ProviderAuthState::SignedOut);
        assert_eq!(retry.credentials_json, result.credentials_json);
    }

    #[test]
    fn uses_pkce_and_requests_only_usage_access() {
        let url = authorization_url(
            "http://localhost:1234/callback",
            "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
            "random-state",
        );
        let pairs = url
            .query_pairs()
            .collect::<std::collections::HashMap<_, _>>();

        assert_eq!(
            pairs["code_challenge"],
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        );
        assert_eq!(pairs["scope"], "user:profile");
        assert_eq!(pairs["state"], "random-state");
    }

    #[test]
    fn accepts_only_callbacks_matching_the_sign_in_attempt() {
        let code = callback_code(
            b"GET /callback?code=accepted&state=expected HTTP/1.1\r\n\r\n",
            "expected",
        )
        .unwrap()
        .unwrap();

        assert_eq!(code, "accepted");

        let invalid_requests = [
            "GET /callback?code=other&state=wrong HTTP/1.1\r\n\r\n",
            "GET /callback?code=other&state=expected&state=wrong HTTP/1.1\r\n\r\n",
            "GET /callback?code=a&code=b&state=expected HTTP/1.1\r\n\r\n",
            "GET /favicon.ico HTTP/1.1\r\n\r\n",
            "POST /callback?code=a&state=expected HTTP/1.1\r\n\r\n",
        ];
        for request in invalid_requests {
            assert!(callback_code(request.as_bytes(), "expected").is_none());
        }
    }

    #[tokio::test]
    async fn ignores_unrelated_requests_and_receives_the_browser_callback() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let receive = tokio::spawn(async move {
            receive_code(
                &listener,
                "expected",
                "Return to AI Usage & close this tab.",
            )
            .await
        });
        let requests = [
            "GET /favicon.ico HTTP/1.1\r\n\r\n",
            "GET /callback?code=accepted&state=expected HTTP/1.1\r\n\r\n",
        ];
        for request in requests {
            let mut stream = tokio::net::TcpStream::connect(address).await.unwrap();
            stream.write_all(request.as_bytes()).await.unwrap();
            let mut response = Vec::new();
            stream.read_to_end(&mut response).await.unwrap();

            let response = String::from_utf8(response).unwrap();
            assert!(response.contains("Return to AI Usage &amp; close this tab."));
            assert!(response.contains("history.replaceState(null, '', '/callback');"));
        }

        assert_eq!(receive.await.unwrap().unwrap(), "accepted");
    }

    #[tokio::test]
    async fn backs_off_usage_rate_limits_without_refreshing_the_session() {
        let now = Utc::now();
        let (url, server) = serve_responses(vec![(
            "GET /usage ",
            "429 Too Many Requests\r\nRetry-After: 1800",
            "rate limited",
        )]);

        let result = refresh_session_at(
            &credentials(now, false),
            now,
            &format!("{url}token"),
            &format!("{url}usage"),
        )
        .await;
        let saved: Value = serde_json::from_str(&result.credentials_json).unwrap();

        assert_eq!(saved["aiUsageRefresh"]["retryAt"], now.timestamp() + 1800);
        assert_eq!(saved["claudeAiOauth"]["accessToken"], "original-access");
        assert_eq!(result.snapshot.auth_state, ProviderAuthState::Configured);
        server.join().unwrap();
    }

    fn serve_responses(
        responses: Vec<(&'static str, &'static str, &'static str)>,
    ) -> (String, JoinHandle<Vec<String>>) {
        let listener = TestListener::bind("127.0.0.1:0").unwrap();
        listener.set_nonblocking(true).unwrap();
        let base_url = format!("http://{}/", listener.local_addr().unwrap());
        let server = thread::spawn(move || {
            let mut requests = Vec::new();

            for response in responses {
                let (expected_request, status, body) = response;
                let deadline = Instant::now() + Duration::from_secs(5);
                let mut stream = loop {
                    match listener.accept() {
                        Ok((stream, _)) => break stream,
                        Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                            assert!(
                                Instant::now() < deadline,
                                "Missing request: {expected_request}"
                            );
                            thread::sleep(Duration::from_millis(10));
                        }
                        Err(error) => panic!("Could not accept test request: {error}"),
                    }
                };
                stream
                    .set_read_timeout(Some(Duration::from_secs(5)))
                    .unwrap();

                let mut reader = BufReader::new(&stream);
                let mut request = String::new();
                let mut content_length = 0;

                loop {
                    let mut line = String::new();
                    assert!(reader.read_line(&mut line).unwrap() != 0);
                    request.push_str(&line);

                    if line == "\r\n" {
                        break;
                    }

                    if let Some(value) = line.to_lowercase().strip_prefix("content-length:") {
                        content_length = value.trim().parse().unwrap();
                    }
                }

                let mut request_body = vec![0; content_length];
                reader.read_exact(&mut request_body).unwrap();
                request.push_str(std::str::from_utf8(&request_body).unwrap());
                assert!(
                    request.starts_with(expected_request),
                    "Unexpected request: {request}"
                );
                requests.push(request);

                write!(
                    stream,
                    "HTTP/1.1 {status}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                    body.len()
                )
                .unwrap();
            }

            requests
        });

        (base_url, server)
    }
}
