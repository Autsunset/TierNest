// SPDX-License-Identifier: LGPL-3.0-only
// Narrow bridge around the pinned EasyTier mobile core. No TCP management
// server, configuration, credentials or raw logs are exposed to callers.
use easytier::{
    common::{
        config::{ConfigFileControl, TomlConfigLoader},
        global_ctx::{EventBusSubscriber, GlobalCtxEvent},
    },
    instance::factory::{
        NativeInstanceManager, native_instance_manager_with_runtime,
        subscribe_native_instance_event,
    },
    proto::api::{
        instance::PeerInfo,
        manage::{MyNodeInfo, NetworkInstanceRunningInfo},
    },
};
use easytier_core::instance::CoreInstanceState;
use jni::{
    JNIEnv,
    objects::{JClass, JString},
    sys::{jint, jstring},
};
use once_cell::sync::Lazy;
use serde_json::{Value, json};
use std::{collections::HashMap, ptr, sync::Mutex, time::Duration};

struct Engine {
    manager: NativeInstanceManager,
    runtime: tokio::runtime::Runtime,
    id: uuid::Uuid,
}
static ENGINE: Lazy<Mutex<Option<Engine>>> = Lazy::new(|| Mutex::new(None));

fn input(env: &mut JNIEnv, text: JString) -> Result<String, ()> {
    let value: String = env.get_string(&text).map_err(|_| ())?.into();
    if value.len() > 256 * 1024 {
        return Err(());
    }
    Ok(value)
}

fn fail(env: &mut JNIEnv, message: &str) -> jint {
    let _ = env.throw_new("java/lang/IllegalStateException", message);
    -1
}

fn snapshot(info: &NetworkInstanceRunningInfo) -> Value {
    let node = info.my_node_info.as_ref();
    let cidr = node
        .and_then(|v| v.virtual_ipv4.as_ref())
        .map(ToString::to_string)
        .unwrap_or_default();
    let mut rx = 0u64;
    let mut tx = 0u64;
    let mut latencies = HashMap::with_capacity(info.peers.len());
    for peer in &info.peers {
        let mut latency = None;
        for connection in &peer.conns {
            if let Some(stats) = connection.stats.as_ref() {
                rx = rx.saturating_add(stats.rx_bytes);
                tx = tx.saturating_add(stats.tx_bytes);
                latency =
                    Some(latency.map_or(stats.latency_us, |old: u64| old.min(stats.latency_us)));
            }
        }
        latencies.entry(peer.peer_id).or_insert(latency);
    }
    let mut routes = HashMap::with_capacity(info.routes.len());
    for route in &info.routes {
        routes.entry(route.peer_id).or_insert(route);
    }
    let mut peers = vec![
        json!({"hostname": node.map(|n| n.hostname.as_str()).unwrap_or(""),
        "ipv4": cidr, "path_len": 0, "proxy_cidrs": "", "next_hop_hostname": "Local",
        "peer_id": node.map(|n| n.peer_id.to_string()).unwrap_or_default(),
        "version": node.map(|n| n.version.as_str()).unwrap_or("")}),
    ];
    for route in &info.routes {
        let next = routes.get(&route.next_hop_peer_id).copied();
        let latency = latencies
            .get(&route.next_hop_peer_id)
            .copied()
            .flatten()
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

async fn network_snapshot(manager: &NativeInstanceManager, id: uuid::Uuid) -> Option<Value> {
    let instance = manager.instance(id)?;
    // The manager now registers an instance before its async start task runs.
    // Created is pending, not a core exit during the first Android status tick.
    if instance.state() == CoreInstanceState::Created {
        return Some(json!({"alive": true, "pending": true, "peers": []}));
    }
    let mut info = NetworkInstanceRunningInfo {
        running: instance.state() != CoreInstanceState::Stopped,
        error_msg: instance.latest_error(),
        ..Default::default()
    };
    if instance.is_ready() {
        // The full management snapshot clones events/foreign networks and builds
        // an O(routes * peers) pairing list that Android never consumes.
        info.peers = instance
            .peer_snapshots()
            .await
            .into_iter()
            .map(|peer| PeerInfo {
                peer_id: peer.peer_id,
                conns: peer.conns.into_iter().map(Into::into).collect(),
                ..Default::default()
            })
            .collect();
        let node = instance.node_snapshot().await;
        info.my_node_info = Some(MyNodeInfo {
            peer_id: node.peer_id,
            hostname: node.hostname,
            version: node.version,
            virtual_ipv4: node.ipv4_addr.map(Into::into),
            ..Default::default()
        });
        info.routes = instance
            .route_snapshots()
            .await
            .into_iter()
            .map(Into::into)
            .collect();
    }
    Some(snapshot(&info))
}

async fn tun_ready(events: &mut EventBusSubscriber, fd: jint) -> bool {
    let expected = format!("tunfd_{fd}");
    loop {
        match events.recv().await {
            Ok(GlobalCtxEvent::TunDeviceReady(name)) if name == expected => return true,
            Ok(GlobalCtxEvent::TunDeviceError(_)) | Err(_) => return false,
            _ => {}
        }
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_tiernest_app_engine_NativeVpn_validate(
    mut env: JNIEnv,
    _: JClass,
    text: JString,
) -> jint {
    let Ok(text) = input(&mut env, text) else {
        return fail(&mut env, "Invalid configuration text");
    };
    match TomlConfigLoader::new_from_str(&text) {
        Ok(_) => 0,
        Err(_) => fail(&mut env, "EasyTier rejected the configuration"),
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_tiernest_app_engine_NativeVpn_start(
    mut env: JNIEnv,
    _: JClass,
    text: JString,
) -> jint {
    let Ok(text) = input(&mut env, text) else {
        return fail(&mut env, "Invalid configuration text");
    };
    let Ok(config) = TomlConfigLoader::new_from_str(&text) else {
        return fail(&mut env, "EasyTier rejected the configuration");
    };
    let Ok(mut slot) = ENGINE.lock() else {
        return fail(&mut env, "Native engine lock failed");
    };
    if slot.is_some() {
        return fail(&mut env, "VPN engine is already running");
    }
    let Ok(runtime) = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(1)
        .enable_all()
        .build()
    else {
        return fail(&mut env, "Cannot create VPN runtime");
    };
    let manager = native_instance_manager_with_runtime(runtime.handle().clone());
    let id = {
        let _guard = runtime.enter();
        match manager.run_network_instance(config, ConfigFileControl::STATIC_CONFIG) {
            Ok(id) => id,
            Err(_) => return fail(&mut env, "Cannot start EasyTier VPN instance"),
        }
    };
    *slot = Some(Engine {
        manager,
        runtime,
        id,
    });
    0
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_tiernest_app_engine_NativeVpn_snapshot(
    mut env: JNIEnv,
    _: JClass,
) -> jstring {
    let Ok(slot) = ENGINE.lock() else {
        fail(&mut env, "Native engine lock failed");
        return ptr::null_mut();
    };
    let value = match slot.as_ref() {
        None => json!({"alive": false, "peers": []}),
        Some(engine) => {
            match engine.runtime.block_on(async {
                tokio::time::timeout(
                    Duration::from_secs(5),
                    network_snapshot(&engine.manager, engine.id),
                )
                .await
            }) {
                Ok(Some(info)) => info,
                Ok(None) => json!({"alive": false, "failed": true, "peers": []}),
                Err(_) => {
                    fail(&mut env, "VPN status timed out");
                    return ptr::null_mut();
                }
            }
        }
    };
    env.new_string(value.to_string())
        .map(|s| s.into_raw())
        .unwrap_or(ptr::null_mut())
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_tiernest_app_engine_NativeVpn_setTunFd(
    mut env: JNIEnv,
    _: JClass,
    fd: jint,
) -> jint {
    let Ok(slot) = ENGINE.lock() else {
        return fail(&mut env, "Native engine lock failed");
    };
    let Some(engine) = slot.as_ref() else {
        return fail(&mut env, "VPN engine is not running");
    };
    let Some(mut events) = engine
        .manager
        .instance(engine.id)
        .and_then(|instance| subscribe_native_instance_event(&instance))
    else {
        return fail(&mut env, "VPN instance event source is unavailable");
    };
    // Android's EasyTier device sets close_fd_on_drop(false). Java owns the PFD.
    if fd <= 0 || engine.manager.attach_tun_fd(engine.id, fd).is_err() {
        return fail(&mut env, "Cannot attach the Android VPN interface");
    }
    // Wait for the mobile NIC's acknowledgement, so Java can close the old PFD
    // without racing an asynchronous descriptor handoff. Subscribe before attach
    // instead of collecting all peers and routes every 20 ms to inspect events.
    let ready = engine.runtime.block_on(async {
        tokio::time::timeout(Duration::from_secs(5), tun_ready(&mut events, fd)).await
    });
    if matches!(ready, Ok(true)) {
        0
    } else {
        fail(&mut env, "VPN interface was not accepted by the core")
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_tiernest_app_engine_NativeVpn_stop(
    mut env: JNIEnv,
    _: JClass,
) -> jint {
    let Ok(mut slot) = ENGINE.lock() else {
        return fail(&mut env, "Native engine lock failed");
    };
    if let Some(engine) = slot.take() {
        let result = engine
            .runtime
            .block_on(engine.manager.retain_network_instances(&[]));
        drop(engine.manager);
        engine.runtime.shutdown_timeout(Duration::from_secs(2));
        if result.is_err() {
            return fail(&mut env, "VPN core cleanup failed");
        }
    }
    0
}

#[cfg(test)]
mod tests {
    use super::*;
    use easytier::proto::api::instance::{PeerConnInfo, PeerConnStats, Route};

    fn runtime() -> tokio::runtime::Runtime {
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
    }

    fn connection(rx: u64, tx: u64, latency: u64) -> PeerConnInfo {
        PeerConnInfo {
            stats: Some(PeerConnStats {
                rx_bytes: rx,
                tx_bytes: tx,
                latency_us: latency,
                ..Default::default()
            }),
            ..Default::default()
        }
    }

    #[test]
    fn snapshot_indexes_next_hops_and_keeps_unknown_latency_null() {
        let info = NetworkInstanceRunningInfo {
            running: true,
            my_node_info: Some(MyNodeInfo {
                hostname: "fixture-local".into(),
                peer_id: 1,
                version: "2.7.0".into(),
                ..Default::default()
            }),
            peers: vec![PeerInfo {
                peer_id: 2,
                conns: vec![connection(90, 30, 4_000), connection(10, 20, 1_500)],
                ..Default::default()
            }],
            routes: vec![
                Route {
                    peer_id: 3,
                    next_hop_peer_id: 2,
                    cost: 2,
                    hostname: "fixture-leaf".into(),
                    proxy_cidrs: vec!["198.51.100.0/24".into()],
                    ..Default::default()
                },
                Route {
                    peer_id: 2,
                    next_hop_peer_id: 2,
                    cost: 1,
                    hostname: "fixture-relay".into(),
                    ..Default::default()
                },
                Route {
                    peer_id: 4,
                    next_hop_peer_id: 99,
                    cost: 3,
                    ..Default::default()
                },
            ],
            ..Default::default()
        };
        let value = snapshot(&info);
        assert_eq!(value["alive"], true);
        assert_eq!(value["failed"], false);
        assert_eq!(value["rx"], 100);
        assert_eq!(value["tx"], 50);
        assert_eq!(value["peers"][0]["hostname"], "fixture-local");
        assert_eq!(value["peers"][0]["path_len"], 0);
        assert_eq!(value["peers"][1]["next_hop_hostname"], "fixture-relay");
        assert_eq!(value["peers"][1]["next_hop_lat"], 1.5);
        assert_eq!(value["peers"][1]["proxy_cidrs"], "198.51.100.0/24");
        assert_eq!(value["peers"][2]["next_hop_hostname"], "DIRECT");
        assert!(value["peers"][3]["next_hop_lat"].is_null());
        assert_eq!(value["peers"][3]["next_hop_hostname"], "");
    }

    #[test]
    fn snapshot_saturates_totals_and_reports_core_failure() {
        let info = NetworkInstanceRunningInfo {
            error_msg: Some("fixture failure".into()),
            peers: vec![PeerInfo {
                conns: vec![connection(u64::MAX, u64::MAX, 0), connection(1, 1, 0)],
                ..Default::default()
            }],
            ..Default::default()
        };
        let value = snapshot(&info);
        assert_eq!(value["rx"].as_u64(), Some(u64::MAX));
        assert_eq!(value["tx"].as_u64(), Some(u64::MAX));
        assert_eq!(value["alive"], false);
        assert_eq!(value["failed"], true);
        assert!(!value.to_string().contains("fixture failure"));
    }

    #[test]
    fn snapshot_duplicate_ids_preserve_the_first_record_even_without_stats() {
        let info = NetworkInstanceRunningInfo {
            peers: vec![
                PeerInfo {
                    peer_id: 2,
                    ..Default::default()
                },
                PeerInfo {
                    peer_id: 2,
                    conns: vec![connection(10, 20, 1_000)],
                    ..Default::default()
                },
            ],
            routes: vec![
                Route {
                    peer_id: 2,
                    hostname: "fixture-first".into(),
                    ..Default::default()
                },
                Route {
                    peer_id: 2,
                    hostname: "fixture-second".into(),
                    ..Default::default()
                },
                Route {
                    peer_id: 3,
                    next_hop_peer_id: 2,
                    cost: 2,
                    ..Default::default()
                },
            ],
            ..Default::default()
        };
        let value = snapshot(&info);
        assert_eq!(value["peers"][3]["next_hop_hostname"], "fixture-first");
        assert!(value["peers"][3]["next_hop_lat"].is_null());
        assert_eq!(value["rx"], 10);
        assert_eq!(value["tx"], 20);
    }

    #[test]
    fn newly_registered_instance_is_pending_before_async_start() {
        let runtime = runtime();
        let manager = native_instance_manager_with_runtime(runtime.handle().clone());
        let config = TomlConfigLoader::new_from_str(
            "hostname = 'fixture-pending'\nlisteners = []\n[flags]\nno_tun = true\n",
        )
        .unwrap();
        let instance = manager.create(config, ()).unwrap();
        let value = runtime
            .block_on(network_snapshot(&manager, instance.instance_id()))
            .unwrap();
        assert_eq!(value["alive"], true);
        assert_eq!(value["pending"], true);
        assert!(
            runtime
                .block_on(network_snapshot(&manager, uuid::Uuid::nil()))
                .is_none()
        );
    }

    #[test]
    fn native_instance_starts_samples_and_awaits_complete_shutdown() {
        let runtime = runtime();
        let manager = native_instance_manager_with_runtime(runtime.handle().clone());
        let config = TomlConfigLoader::new_from_str(
            "hostname = 'fixture-lifecycle'\nipv4 = '10.77.0.1/24'\nlisteners = []\n\
             stun_servers = []\nstun_servers_v6 = []\ntcp_stun_servers = []\n\
             [flags]\nno_tun = true\nenable_ipv6 = false\ndisable_upnp = true\n\
             disable_tcp_hole_punching = true\ndisable_udp_hole_punching = true\n",
        )
        .unwrap();
        runtime.block_on(async {
            let id = manager
                .run_network_instance(config, ConfigFileControl::STATIC_CONFIG)
                .unwrap();
            let value = tokio::time::timeout(Duration::from_secs(5), async {
                loop {
                    let value = network_snapshot(&manager, id).await.unwrap();
                    assert_ne!(value["failed"], true);
                    if value["cidr"] == "10.77.0.1/24" {
                        break value;
                    }
                    tokio::time::sleep(Duration::from_millis(5)).await;
                }
            })
            .await
            .unwrap();
            assert_eq!(value["alive"], true);
            assert_eq!(value["peers"][0]["hostname"], "fixture-lifecycle");
            assert!(
                value["peers"][0]["version"]
                    .as_str()
                    .unwrap()
                    .starts_with("2.7.0")
            );
            tokio::time::timeout(
                Duration::from_secs(5),
                manager.retain_network_instances(&[]),
            )
            .await
            .unwrap()
            .unwrap();
            assert!(manager.instance_ids().is_empty());
            assert!(network_snapshot(&manager, id).await.is_none());
        });
    }

    #[test]
    fn tun_handoff_accepts_buffered_ack_for_only_the_requested_descriptor() {
        let (events, mut receiver) = tokio::sync::broadcast::channel(4);
        events.send(GlobalCtxEvent::PeerAdded(2)).unwrap();
        events
            .send(GlobalCtxEvent::TunDeviceReady("tunfd_8".into()))
            .unwrap();
        events
            .send(GlobalCtxEvent::TunDeviceReady("tunfd_9".into()))
            .unwrap();
        assert!(runtime().block_on(tun_ready(&mut receiver, 9)));
    }

    #[test]
    fn tun_handoff_rejects_error_or_closed_event_source() {
        let (events, mut receiver) = tokio::sync::broadcast::channel(1);
        events
            .send(GlobalCtxEvent::TunDeviceError("fixture failure".into()))
            .unwrap();
        assert!(!runtime().block_on(tun_ready(&mut receiver, 9)));
        drop(events);
        assert!(!runtime().block_on(tun_ready(&mut receiver, 9)));
    }

    #[test]
    fn tun_handoff_does_not_acknowledge_a_dropped_event() {
        let (events, mut receiver) = tokio::sync::broadcast::channel(1);
        events
            .send(GlobalCtxEvent::TunDeviceReady("tunfd_9".into()))
            .unwrap();
        events.send(GlobalCtxEvent::PeerAdded(2)).unwrap();
        assert!(!runtime().block_on(tun_ready(&mut receiver, 9)));
    }
}
