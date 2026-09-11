//! Opt-in product telemetry ingestion and aggregate-only admin reporting.
//!
//! The endpoint deliberately accepts a narrow event schema. It never accepts
//! source, prompts, paths, account data, serial numbers, or hardware UUIDs.

use axum::{
    http::{HeaderMap, StatusCode},
    response::{Html, IntoResponse},
    Json,
};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::PathBuf;
use tokio::fs::{self, OpenOptions};
use tokio::io::AsyncWriteExt;

const MAX_BATCH_SIZE: usize = 100;
const MAX_EVENT_BYTES: usize = 16 * 1024;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
pub struct TelemetryEnvelope {
    pub schema_version: u8,
    pub events: Vec<TelemetryEvent>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
pub struct TelemetryEvent {
    pub event_id: String,
    pub install_id: String,
    pub timestamp: String,
    pub name: String,
    pub mode: Option<String>,
    pub app_version: String,
    pub device: DeviceSnapshot,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
pub struct DeviceSnapshot {
    pub hardware_model: String,
    pub cpu: String,
    pub physical_cpu_count: u16,
    pub logical_cpu_count: u16,
    pub memory_bytes: u64,
    pub gpu_names: Vec<String>,
    pub has_apple_neural_engine: bool,
    pub operating_system: String,
    pub architecture: String,
}

pub async fn ingest(Json(envelope): Json<TelemetryEnvelope>) -> impl IntoResponse {
    if envelope.schema_version != 1
        || envelope.events.is_empty()
        || envelope.events.len() > MAX_BATCH_SIZE
    {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "invalid telemetry batch"})),
        )
            .into_response();
    }
    if envelope.events.iter().any(|event| !is_valid(event)) {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "invalid telemetry event"})),
        )
            .into_response();
    }

    let path = telemetry_log_path();
    if let Some(parent) = path.parent() {
        if let Err(error) = fs::create_dir_all(parent).await {
            tracing::error!(?error, "unable to create telemetry directory");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    }

    let mut file = match OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .await
    {
        Ok(file) => file,
        Err(error) => {
            tracing::error!(?error, ?path, "unable to open telemetry log");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    for event in &envelope.events {
        match serde_json::to_vec(event) {
            Ok(mut record) => {
                record.push(b'\n');
                if file.write_all(&record).await.is_err() {
                    return StatusCode::INTERNAL_SERVER_ERROR.into_response();
                }
            }
            Err(_) => return StatusCode::BAD_REQUEST.into_response(),
        }
    }
    (
        StatusCode::ACCEPTED,
        Json(serde_json::json!({"accepted": envelope.events.len()})),
    )
        .into_response()
}

pub async fn admin_summary(headers: HeaderMap) -> impl IntoResponse {
    if !is_admin(&headers) {
        return StatusCode::UNAUTHORIZED.into_response();
    }

    let records = read_events().await;
    let mut installations = std::collections::BTreeSet::new();
    let mut event_names = BTreeMap::<String, u64>::new();
    let mut modes = BTreeMap::<String, u64>::new();
    let mut versions = BTreeMap::<String, u64>::new();
    let mut models = BTreeMap::<String, u64>::new();
    let mut cpus = BTreeMap::<String, u64>::new();
    let mut memory_classes = BTreeMap::<String, u64>::new();
    let mut gpu_names = BTreeMap::<String, u64>::new();
    let mut operating_systems = BTreeMap::<String, u64>::new();
    let mut architectures = BTreeMap::<String, u64>::new();
    let mut daily_events = BTreeMap::<String, u64>::new();
    let mut first_seen: Option<String> = None;
    let mut last_seen: Option<String> = None;
    for record in &records {
        installations.insert(record.install_id.clone());
        *event_names.entry(record.name.clone()).or_default() += 1;
        if let Some(mode) = &record.mode {
            *modes.entry(mode.clone()).or_default() += 1;
        }
        *versions.entry(record.app_version.clone()).or_default() += 1;
        *models
            .entry(record.device.hardware_model.clone())
            .or_default() += 1;
        *cpus.entry(record.device.cpu.clone()).or_default() += 1;
        let memory_gib =
            (record.device.memory_bytes + (1024 * 1024 * 1024 - 1)) / (1024 * 1024 * 1024);
        *memory_classes
            .entry(format!("{memory_gib} GiB"))
            .or_default() += 1;
        for gpu in &record.device.gpu_names {
            *gpu_names.entry(gpu.clone()).or_default() += 1;
        }
        *operating_systems
            .entry(record.device.operating_system.clone())
            .or_default() += 1;
        *architectures
            .entry(record.device.architecture.clone())
            .or_default() += 1;
        if let Some(day) = record
            .timestamp
            .get(..10)
            .filter(|value| value.chars().all(|c| c.is_ascii_digit() || c == '-'))
        {
            *daily_events.entry(day.to_owned()).or_default() += 1;
        }
        if first_seen
            .as_ref()
            .is_none_or(|current| record.timestamp < *current)
        {
            first_seen = Some(record.timestamp.clone());
        }
        if last_seen
            .as_ref()
            .is_none_or(|current| record.timestamp > *current)
        {
            last_seen = Some(record.timestamp.clone());
        }
    }
    Json(serde_json::json!({
        "eventCount": records.len(),
        "anonymousInstallCount": installations.len(),
        "firstSeen": first_seen,
        "lastSeen": last_seen,
        "eventsByName": event_names,
        "modeOpens": modes,
        "appVersions": versions,
        "hardwareModels": models,
        "cpus": cpus,
        "memoryClasses": memory_classes,
        "gpuNames": gpu_names,
        "operatingSystems": operating_systems,
        "architectures": architectures,
        "dailyEvents": daily_events,
        "privacy": "Aggregate-only: no source code, prompts, project/file names, paths, terminal commands, account email, hardware UUID, or serial number.",
        "retention": "configure TELEMETRY_LOG_PATH and rotate it according to your privacy policy"
    })).into_response()
}

/// A dependency-free administrative UI. Authentication happens in the API;
/// the token stays in this browser tab's session storage and is never written
/// to the server, a URL, or persistent browser storage.
pub async fn admin_dashboard() -> Html<&'static str> {
    Html(
        r###"<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>MicroCode Admin · Usage</title><style>
:root{color-scheme:dark;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#111;color:#eee}body{margin:0;background:#111}.wrap{max-width:1180px;margin:auto;padding:32px}.bar{display:flex;gap:12px;align-items:center;flex-wrap:wrap}.bar h1{margin:0 auto 0 0;font-size:24px}.bar input{width:280px;max-width:60vw;padding:10px 12px;border:1px solid #444;border-radius:9px;background:#1c1c1e;color:#fff}.bar button{padding:10px 14px;border:0;border-radius:9px;background:#0a84ff;color:#fff;font-weight:650;cursor:pointer}.meta,#status{color:#aaa;font-size:13px;margin:14px 0}.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(175px,1fr));gap:12px}.card,section{background:#1c1c1e;border:1px solid #2d2d31;border-radius:12px;padding:16px}.card b{font-size:28px;display:block}.card span{font-size:12px;color:#aaa}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:12px;margin-top:12px}section h2{font-size:14px;margin:0 0 10px;color:#ddd}table{width:100%;border-collapse:collapse;font-size:12px}td{padding:7px 0;border-top:1px solid #303035}td:last-child{text-align:right;color:#bbb}.error{color:#ff9f0a}.empty{color:#888;font-size:13px}</style></head>
<body><div class="wrap"><div class="bar"><h1>MicroCode Admin · Privacy-safe usage</h1><input id="token" type="password" placeholder="Telemetry admin token"><button id="load">Load data</button></div><div id="status">Enter the server-side telemetry admin token.</div><div id="cards" class="cards"></div><main id="details"></main><p class="meta">This dashboard displays aggregates only. It never receives source code, prompts, project names, file paths, terminal commands, email, serial numbers, or hardware UUIDs.</p></div>
<script>const $=id=>document.getElementById(id),token=$('token'),status=$('status'),cards=$('cards'),details=$('details');token.value=sessionStorage.getItem('microcodeTelemetryToken')||'';function esc(v){const d=document.createElement('div');d.textContent=String(v);return d.innerHTML}function section(title,rows){const entries=Object.entries(rows||{});return `<section><h2>${esc(title)}</h2>${entries.length?`<table>${entries.map(([k,v])=>`<tr><td>${esc(k)}</td><td>${esc(v)}</td></tr>`).join('')}</table>`:'<p class="empty">No data yet</p>'}</section>`}function render(d){cards.innerHTML=[['Anonymous installs',d.anonymousInstallCount],['Events',d.eventCount],['First seen',d.firstSeen||'—'],['Last seen',d.lastSeen||'—']].map(([k,v])=>`<div class="card"><b>${esc(v)}</b><span>${esc(k)}</span></div>`).join('');details.innerHTML=[['Events',d.eventsByName],['Mode opens',d.modeOpens],['App versions',d.appVersions],['Daily events',d.dailyEvents],['Hardware models',d.hardwareModels],['CPU',d.cpus],['Memory',d.memoryClasses],['GPU',d.gpuNames],['Operating systems',d.operatingSystems],['Architecture',d.architectures]].map(([k,v])=>section(k,v)).join('');status.textContent=d.privacy+' '+d.retention}async function load(){const value=token.value.trim();if(!value){status.textContent='Admin token is required.';status.className='error';return}sessionStorage.setItem('microcodeTelemetryToken',value);status.textContent='Loading…';status.className='';try{const r=await fetch('/api/admin/telemetry/summary',{headers:{Authorization:`Bearer ${value}`}});if(!r.ok)throw Error(r.status===401?'Unauthorized — check TELEMETRY_ADMIN_TOKEN.':`Request failed (${r.status})`);render(await r.json());status.className=''}catch(e){status.textContent=e.message;status.className='error'}}$('load').onclick=load;</script></body></html>"###,
    )
}

fn is_valid(event: &TelemetryEvent) -> bool {
    let known_event = matches!(
        event.name.as_str(),
        "app_launch" | "mode_opened" | "telemetry_consent_granted"
    );
    let known_mode = event
        .mode
        .as_deref()
        .map(|mode| {
            matches!(
                mode,
                "code"
                    | "science"
                    | "playground"
                    | "notebook"
                    | "scenario"
                    | "design"
                    | "Remote X"
                    | "Embedded Studio"
                    | "AI Agent"
                    | "Browser"
            )
        })
        .unwrap_or(true);
    known_event
        && known_mode
        && (6..=64).contains(&event.install_id.len())
        && event.event_id.len() <= 64
        && event.app_version.len() <= 128
        && event.timestamp.len() <= 64
        && serde_json::to_vec(event)
            .map(|bytes| bytes.len() <= MAX_EVENT_BYTES)
            .unwrap_or(false)
}

fn is_admin(headers: &HeaderMap) -> bool {
    let expected = match std::env::var("TELEMETRY_ADMIN_TOKEN") {
        Ok(value) if !value.is_empty() => value,
        _ => return false,
    };
    headers
        .get("authorization")
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))
        .is_some_and(|token| token == expected)
}

fn telemetry_log_path() -> PathBuf {
    if let Ok(path) = std::env::var("TELEMETRY_LOG_PATH") {
        return PathBuf::from(path);
    }
    dirs::data_local_dir()
        .unwrap_or_else(std::env::temp_dir)
        .join("MicroCode")
        .join("telemetry.ndjson")
}

async fn read_events() -> Vec<TelemetryEvent> {
    let Ok(contents) = fs::read_to_string(telemetry_log_path()).await else {
        return Vec::new();
    };
    contents
        .lines()
        .filter_map(|line| serde_json::from_str(line).ok())
        .collect()
}
