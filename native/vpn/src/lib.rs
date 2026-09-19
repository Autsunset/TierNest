// SPDX-License-Identifier: LGPL-3.0-only
// Narrow bridge around the pinned EasyTier mobile core. No TCP management
// server, configuration, credentials or raw logs are exposed to callers.
use easytier::{
    common::config::{ConfigFileControl, TomlConfigLoader},
    instance_manager::NetworkInstanceManager,
    proto::api::manage::NetworkInstanceRunningInfo,
};
use jni::{JNIEnv, objects::{JClass, JString}, sys::{jint, jstring}};
use once_cell::sync::Lazy;
use serde_json::{Value, json};
use std::{ptr, sync::Mutex, time::Duration};

struct Engine {
    manager: NetworkInstanceManager,
    runtime: tokio::runtime::Runtime,
    id: uuid::Uuid,
}
static ENGINE: Lazy<Mutex<Option<Engine>>> = Lazy::new(|| Mutex::new(None));

fn input(env: &mut JNIEnv, text: JString) -> Result<String, ()> {
    let value: String = env.get_string(&text).map_err(|_| ())?.into();
    if value.len() > 256 * 1024 { return Err(()); }
    Ok(value)
}

fn fail(env: &mut JNIEnv, message: &str) -> jint {
    let _ = env.throw_new("java/lang/IllegalStateException", message);
    -1
}

fn snapshot(info: &NetworkInstanceRunningInfo) -> Value {
    let node = info.my_node_info.as_ref();
    let cidr = node.and_then(|v| v.virtual_ipv4.as_ref()).map(ToString::to_string).unwrap_or_default();
    let mut rx = 0u64;
    let mut tx = 0u64;
    for peer in &info.peers {
        for connection in &peer.conns {
            if let Some(stats) = connection.stats.as_ref() {
                rx = rx.saturating_add(stats.rx_bytes);
                tx = tx.saturating_add(stats.tx_bytes);
            }
        }
    }
    let mut peers = vec![json!({"hostname": node.map(|n| n.hostname.as_str()).unwrap_or(""),
        "ipv4": cidr, "path_len": 0, "proxy_cidrs": "", "next_hop_hostname": "Local",
        "peer_id": node.map(|n| n.peer_id.to_string()).unwrap_or_default(),
        "version": node.map(|n| n.version.as_str()).unwrap_or("")})];
    for route in &info.routes {
        let next = info.routes.iter().find(|r| r.peer_id == route.next_hop_peer_id);
        let latency = info.peers.iter().find(|p| p.peer_id == route.next_hop_peer_id)
            .and_then(|p| p.conns.iter().filter_map(|c| c.stats.as_ref()).map(|s| s.latency_us).min())
            .map(|us| us as f64 / 1000.0);
        peers.push(json!({
            "hostname": route.hostname,
            "ipv4": route.ipv4_addr.as_ref().map(ToString::to_string).unwrap_or_default(),
            "path_len": route.cost,
            "peer_id": route.peer_id.to_string(), "next_hop_peer_id": route.next_hop_peer_id.to_string(),
            "version": route.version,
            "next_hop_ipv4": next.and_then(|r| r.ipv4_addr.as_ref()).map(ToString::to_string).unwrap_or_default(),
            "proxy_cidrs": route.proxy_cidrs.join(","),
            "next_hop_hostname": if route.cost == 1 { "DIRECT" } else { next.map(|r| r.hostname.as_str()).unwrap_or("") },
            "next_hop_lat": latency,
        }));
    }
    json!({"alive": info.running, "cidr": cidr, "rx": rx, "tx": tx, "peers": peers,
        "failed": info.error_msg.is_some()})
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_tiernest_app_engine_NativeVpn_validate(
    mut env: JNIEnv, _: JClass, text: JString,
) -> jint {
    let Ok(text) = input(&mut env, text) else { return fail(&mut env, "Invalid configuration text"); };
    match TomlConfigLoader::new_from_str(&text) {
        Ok(_) => 0,
        Err(_) => fail(&mut env, "EasyTier rejected the configuration"),
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_tiernest_app_engine_NativeVpn_start(
    mut env: JNIEnv, _: JClass, text: JString,
) -> jint {
    let Ok(text) = input(&mut env, text) else { return fail(&mut env, "Invalid configuration text"); };
    let Ok(config) = TomlConfigLoader::new_from_str(&text) else { return fail(&mut env, "EasyTier rejected the configuration"); };
    let Ok(mut slot) = ENGINE.lock() else { return fail(&mut env, "Native engine lock failed"); };
    if slot.is_some() { return fail(&mut env, "VPN engine is already running"); }
    let Ok(runtime) = tokio::runtime::Builder::new_multi_thread().worker_threads(1).enable_all().build()
        else { return fail(&mut env, "Cannot create VPN runtime"); };
    let manager = NetworkInstanceManager::new();
    let id = {
        let _guard = runtime.enter();
        match manager.run_network_instance(config, true, ConfigFileControl::STATIC_CONFIG) {
            Ok(id) => id,
            Err(_) => return fail(&mut env, "Cannot start EasyTier VPN instance"),
        }
    };
    *slot = Some(Engine { manager, runtime, id });
    0
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_tiernest_app_engine_NativeVpn_snapshot(
    mut env: JNIEnv, _: JClass,
) -> jstring {
    let Ok(slot) = ENGINE.lock() else { fail(&mut env, "Native engine lock failed"); return ptr::null_mut(); };
    let value = match slot.as_ref() {
        None => json!({"alive": false, "peers": []}),
        Some(engine) => {
            match engine.runtime.block_on(async {
                tokio::time::timeout(Duration::from_secs(5), engine.manager.get_network_info(&engine.id)).await
            }) {
                Ok(Some(info)) => snapshot(&info),
                Ok(None) => json!({"alive": true, "pending": true, "peers": []}),
                Err(_) => { fail(&mut env, "VPN status timed out"); return ptr::null_mut(); }
            }
        }
    };
    env.new_string(value.to_string()).map(|s| s.into_raw()).unwrap_or(ptr::null_mut())
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_tiernest_app_engine_NativeVpn_setTunFd(
    mut env: JNIEnv, _: JClass, fd: jint,
) -> jint {
    let Ok(slot) = ENGINE.lock() else { return fail(&mut env, "Native engine lock failed"); };
    let Some(engine) = slot.as_ref() else { return fail(&mut env, "VPN engine is not running"); };
    fn latest_tun_event(info: &NetworkInstanceRunningInfo) -> Option<(String, bool)> {
        info.events.iter().find_map(|event| {
            let json: Value = serde_json::from_str(event).ok()?;
            let detail = json.get("event")?;
            if detail.get("TunDeviceReady").is_some() { Some((event.clone(), true)) }
            else if detail.get("TunDeviceError").is_some() { Some((event.clone(), false)) }
            else { None }
        })
    }
    let before = engine.runtime.block_on(engine.manager.get_network_info(&engine.id))
        .as_ref().and_then(latest_tun_event);
    // Android's EasyTier device sets close_fd_on_drop(false). Java owns the PFD.
    if fd < 0 || engine.manager.set_tun_fd(&engine.id, fd).is_err() {
        return fail(&mut env, "Cannot attach the Android VPN interface");
    }
    // Wait for the mobile NIC's acknowledgement, so Java can close the old PFD
    // without racing an asynchronous descriptor handoff.
    let ready = engine.runtime.block_on(async {
        tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                if let Some(info) = engine.manager.get_network_info(&engine.id).await {
                    let event = latest_tun_event(&info);
                    if event.is_some() && event != before { return event.unwrap().1; }
                }
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
        }).await
    });
    if matches!(ready, Ok(true)) { 0 } else { fail(&mut env, "VPN interface was not accepted by the core") }
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_tiernest_app_engine_NativeVpn_stop(
    mut env: JNIEnv, _: JClass,
) -> jint {
    let Ok(mut slot) = ENGINE.lock() else { return fail(&mut env, "Native engine lock failed"); };
    if let Some(engine) = slot.take() {
        let result = {
            let _guard = engine.runtime.enter();
            engine.manager.retain_network_instance(Vec::new())
        };
        drop(engine.manager);
        engine.runtime.shutdown_timeout(Duration::from_secs(2));
        if result.is_err() { return fail(&mut env, "VPN core cleanup failed"); }
    }
    0
}
