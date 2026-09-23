# Changelog

## App 0.2.0-rc03 - 2026-09-23

- 修复 rc02 的息屏维护调度：网络、热点和用户事件现在重置退避计数；非定时 HTTP 模式中，事件接近强制核对期限时，下一次 Root 路由核对仍按原截止时间安排，不会因重新计时延后。
- 非定时 HTTP 模式下，Root 策略表租约丢失时恢复 60 秒基础节奏；VPN 模式继续按原有稳定路由退避，不受 Root 租约判断影响。
- 保持 rc02 的签名、包名和用户配置继承规则；真机功耗对比、实体 Root 与长期锁屏验收仍待完成。

## App 0.2.0-rc02 - 2026-09-23

- 性能：偏好读取改为缓存并在写入时失效，避免每次采样、协调和磁贴刷新重复解析；每次采样只扫描一次系统网络并在 IO 线程完成；热路径正则预编译；Root `status` 不再重复检查核心并去掉 sed/awk 子进程。行为不变，Root 端改动尚需真机复测。
- 功耗：网络能力回调只在传输类型、VPN/联网/已验证位变化时触发协调，忽略信号强度和计费状态抖动；Root 路由日志与热点规则仅在路由、租约、热点广播或偏好变化时重推，另每 5 分钟强制核对一次；息屏且路由稳定时维护间隔从 60 秒逐步退到最长 5 分钟，亮屏和任何事件立即恢复。
- 行为与 rc01 一致，覆盖升级保留配置与偏好；实体设备验收和功耗对比仍未完成，保持候选标记。

## App 0.2.0-rc01 - 2026-09-21

- 进入正式版候选阶段，增加验收计划、发布流程与剩余实机验证清单。
- Android 8/9 按需请求备份存储权限；允许后继续原操作，拒绝时保留配置与草稿。
- 模块导入先保存审阅限制和停止状态，再提交 TOML；失败主动回滚，无法确认恢复时保留保护状态。配置写入增加显式同步与内容核对。
- 导入缺少系统文件选择器、打开链接缺少浏览器时显示提示；家庭网络复验错误直接显示在列表页。修正文档和界面中的旧热点、备份与检测说明。
- VPN 删除已被更宽路由覆盖的冗余项；同网段节点加入或离开时不再因此重建系统 VPN 接口，覆盖范围不扩大。
- 虚拟 IPv4 提前拒绝不支持的范围；VPN 的 MTU 在原生核心与系统接口间保持一致，避免原始 TOML 绕过表单范围后被单侧截断。
- Root 连接期间的无效草稿先在本地拒绝；校验/备份收到完整的操作失败响应时保留活跃会话，真正的通信错误仍清理。
- 热点清理直接按完整规则删除，失败时区分不存在与查询错误，减少正常清理命令数；保留外来规则、回滚记录和手动停止优先级。
- 发布身份迁入独立私有签名库并固定证书指纹，保持旧版覆盖升级；CI 使用独立包名、名称与签名。增加 APK 身份、非调试标志、原生对齐、二进制清单和隐私检查。
- 增加 Android 8 权限/导入/VPN 实测、迁移失败回归、128 目标热点隔离网络测试与 VPN 连续运行观察。实体 arm64 Root、热点及长期待机尚需验收，保持候选标记。

## 1.1.0 - 2026-09-13

- 自动模式增加事件检测与定时检测选择；旧安装默认继续每 30 秒定时检测。
- WebUI 可保存自定义正整数秒间隔，切换检测方式保留间隔；保存失败保留输入并显示实际设置，重复提交互斥。
- 事件检测使用原生阻塞式 Wi-Fi 通知，覆盖连接、断开、漫游、地址和默认路由变化；合并事件并有限补查，不循环验证 HTTP。首次保存仍需通过原有 Wi-Fi 代理验证。
- 新增 `home-detection.conf` 的原子保存和逐字节升级备份/继承；不进入通用安装包。手动停止、删除最后一个网络和重启规则不变。
- 不支持事件监听时拒绝保存；监听异常退出时恢复核心并显示错误，不能让手机停留在无法恢复的待机状态。
- 添加事件解析、定时/事件循环、子进程回收、保存回滚、间隔边界、迁移及浏览器交互回归。实际 Wi-Fi 切换和待机功耗仍需真机验证。

## 1.0.6 - 2026-09-12

修复 v1.0.4/v1.0.5 安装后选择自动模式报“操作失败”、开机入口无法运行的问题。Root 管理器可能把解压文件统一设为 0644，旧安装器的执行权限列表漏掉了 home_watch.sh 和 service_boot.sh，导致 Permission denied。

安装器现在为模块根目录全部 Shell 脚本设置 0755，避免新增脚本再次遗漏；增加从 0644 初始权限执行安装器的回归检查。运行逻辑、30 秒检测间隔、组网配置及升级继承规则不变。

## 1.0.5 - 2026-09-12

自动模式支持同时记住家庭路由器、随身 Wi-Fi 等多个网络。连接其中任意一个已记住的网关，且经该 Wi-Fi 能访问指定虚拟地址时，手机核心进入“自动待机”；离开这些网络或代理失效时恢复。

- “概览 → 运行方式 → 记住可代理的 Wi-Fi”：连接要添加的网络，填写虚拟网络验证地址及 HTTP 端口，验证并保存。网关 IP、MAC、WLAN 接口自动读取；保存新网络保留已有记录，同一网关重复保存更新验证目标。
- 已保存列表显示网关、MAC、验证地址和当前代理状态，每条可单独移除。移除最后一条时回到手动模式；先前的手动停止状态仍保留。
- 两个已记住且可用的路由器之间切换继续待机。切到不同网关且代理失效时立即恢复；当前同一网关连续两次探测失败时恢复，保留抗瞬时丢包处理。
- 仍使用每 30 秒一次的检查，先匹配网关身份，再强制通过 WLAN 验证虚拟网络访问。手机自己的 EasyTier 或其他 VPN 不作为路由器代理可用的依据。
- v1.0.4 的单网络记录无需改写即可读取，新增记录时转为多记录格式。升级逐字节继承整个记录文件、运行方式及停止状态，通用 ZIP 不包含私人网关信息。

## 1.0.4 - 2026-09-12

后台启动使用独立会话并等待脚本发布 PID，避免关闭 Root 调试连接时收到挂断信号。Android mksh 启动包装函数使用花括号函数体并在后台直接 exec，避免多余子 Shell 转发 SIGHUP。核心 PID 按实际程序重新确认，兼容 setsid 可能产生的进程变化。

概览的“运行方式”提供两个选项，升级默认保持手动模式，不自动替用户启用家庭识别。

- 手动模式：自行启动和停止。停止会退出核心、守护、网络监视及其子进程，清理模块路由；配置保留，重启手机后仍保持停止。WebUI 在手动停止时也暂停定时状态/日志读取，可手动刷新。
- 自动模式：连接家庭 Wi-Fi 时，填写 OpenWrt 的虚拟 IPv4 和 HTTP 端口，点击“验证并记住当前家庭 Wi-Fi”，再应用自动模式。以物理 WLAN 接口、网关 IP/MAC 和强制走 WLAN 的虚拟网络 HTTP 探测判断，避免手机自己的 EasyTier 或 VPN 让探测误成功。
- 在家待机时仅保留每 30 秒检查一次的家庭监视；核心、普通守护和网络快照任务退出。离家后恢复；同一家庭网关连续两次探测失败也恢复，避免 OpenWrt 组网中断后手机失联。识别及恢复有约 30–60 秒检测延迟，核心启动还需要几秒。
- 自动模式下点击停止同样关闭全部后台，自动检测、切换模式和重启手机都不会撤销手动停止；点击启动/重启才解除。路由策略和热点设置也不会擅自解除停止。
- 升级逐字节继承 `service-mode.state`、`home-network.conf`，通用包不包含任何家庭网关或个人虚拟地址。更换路由器或网关 MAC 后重新记住家庭 Wi-Fi。系统须有 curl，HTTP 端口须可经家庭网关访问。

## 1.0.3 - 2026-09-12

- Save configuration snapshots to `/sdcard/Download/TierNest/backups/` and display the full backup path in WebUI.
- Automatically migrate the old backup tree, including upgrade snapshots, into a unique `legacy-*` folder when settings are opened or a configuration backup is created. Verify all file contents before removing the original tree; preserve originals on failure and retry on later actions.
- Handle shared-storage chmod limitations. If Download cannot be written, reject configuration saves without replacing the active TOML. Keep migration out of standby polling.
- Keep the universal package and existing configuration inheritance. Ordinary new snapshots retain the latest 10; migrated history remains in its own folder.

## 1.0.2 - 2026-09-12

- Ship one universal arm64 ZIP for all supported devices and root managers. Retire private/device-bound package generation and use module.prop as the release version source.
- Preserve existing TOML byte-for-byte, command arguments, routing/hotspot preferences, manual stop state and backup history. Device identity and profile revisions can no longer replace user configuration.
- Back up the previous configuration/settings before migration, preserve supported runtime settings and add only missing new defaults. Infer the classic strategy for pre-strategy dedicated-route installations.
- Abort on copy/merge failures, preserve legacy-module disable ownership, and reject shell expressions in inherited settings instead of evaluating them during installation.
- Keep the v1.0.1 network snapshot variable-isolation fix. Existing peer entries are inherited unchanged; this release does not silently remove unreachable peers or claim measured standby savings.
- Add universal migration coverage for the former Mi10, MiPad and Ace3Pro profiles, new installs, legacy migration, command mode, backup collisions, invalid TOML and unsafe settings.

## 1.0.1 - 2026-09-08

- Resolve the Android default physical network when a VPN owns the ordinary route lookup. Do not treat FlClash's tun0 as a Wi-Fi/cellular change.
- Coalesce simultaneous underlay/VPN changes into one restart. Preserve subsequent changes and failed or cooldown-delayed VPN recovery; honor stop/disable/APP conflicts after debounce.
- Isolate transport sampling variables so an unchanged network no longer triggers full diagnostic snapshots every watcher interval.
- Normalize host routes to /32 before comparison, eliminating repeated deletion/recreation of cellular direct routes.
- Allow the surviving network watcher and explicit WebUI start to relaunch a missing daemon, respecting manual stop/disable/remove and official APP VPN. Preserve a surviving watcher's PID when the daemon returns.
- Expose daemon/watcher identity, stop flags, heartbeat, wait channels and recovery stages in status and diagnostics. Log daemon exit/shutdown. A live but blocked daemon is reported, not automatically killed.
- Keep EasyTier 2.6.4, device network identities, profile revisions and routing defaults unchanged. The September 8 interrupted restart and reported heating still require on-device validation; the old report lacks daemon/CPU/temperature evidence.

## 1.0.0 - 2026-09-06

- Release the first major version with the local-routing tree introduced in beta.24; keep EasyTier 2.6.4, module identity, device configurations, profile migration revisions and routing defaults unchanged.
- Separate observed and recovered underlay signatures. Preserve pending changes across debounce, cooldown and restart failures, and honor manual stop/disable/APP-VPN state before recovery.
- Serialize configuration backup/write operations with an owned lock and signal cleanup; use non-overwriting unique backup names, preserve the latest backup during pruning, and recover locks only for verified dead owners.
- Add the namespaced `overview` snapshot API: share expensive UI probes between status and metrics while leaving daemon recovery probes live. Cache module disk usage for five minutes with version/clock validation and atomic publication.
- Coalesce duplicate reads, reject obsolete responses after target changes/backgrounding, and force fresh snapshots after service mutations. Serialize configuration controls and reject writes before the existing configuration has loaded.
- Preserve raw TOML edits when reselecting a view or formatting; refuse invalid visual-mode transitions and expose malformed disk configuration in the raw editor for repair.
- Correct hotspot rollback and stale status races; display unconfirmed state when both the operation and its follow-up read fail.
- Remove duplicate log polling. Match and highlight plaintext before escaped HTML rendering, including literal regex/HTML characters and matches spanning syntax tokens.
- Add isolated regressions for network debounce/cooldown/failure, same-second and concurrent backups, lock ownership/recovery, single-snapshot probe counts, disk cache expiry, request races, log polling/highlighting, and real bundled WebUI failure handling.

## 0.5.0-beta.24 - 2026-09-06

- Replace the geographic map with a compact, scrollable local-routing tree. Remove China/world controls, the location editor, geographic inference and all map dependencies.
- Render direct neighbors, public relays, virtual first hops, and gateway-advertised subnets as distinct node cards. Keep paths and text readable on mobile, preserve selection/scroll on refresh, and highlight the selected route.
- Treat next_hop as the first hop, not necessarily the destination’s immediate neighbor: paths longer than two hops remain explicitly unexpanded/dashed. Missing next hops use non-counted placeholders; contradictory or ambiguous records never become fabricated direct links.
- Preserve public-relay identities when folding them in virtual-only mode; resolve duplicate hostnames with next-hop IP when possible; keep all subnet edges attached to rendered nodes.
- Add pure graph regressions and 360/412/768px browser coverage. Keep legacy location files/APIs only for rollback compatibility and leave device routing/configuration profiles unchanged.

## 0.5.0-beta.23 - 2026-09-06

- Fix geolocated public relays being forced onto the bottom shelf after projection. Cache the offline map projections instead of fitting the world geometry for every node.
- Infer city coordinates from Chinese/English location labels and node names for all device roles; honor explicit coordinates first, validate coordinate ranges and reject ambiguous/incidental name matches. This is offline name inference, not GPS or IP geolocation.
- Preserve real geographic anchors with leader lines when same-city nodes need small display offsets; separate unknown and out-of-view nodes from geographic positions in both map filters.
- Stabilize node selection across latency reordering; avoid treating missing hop counts or stale custom local roles as the local device, and handle direct self-named next hops. Clear removed location configuration on refresh.
- Add geography and browser regressions. Keep beta.22 device identities, configuration migration revisions, and routing strategy defaults unchanged.

## 0.5.0-beta.22 - 2026-09-01

- Add a persistent, manual two-strategy switch in the WebUI with one-click cleanup and EasyTier restart.
- **Official-compatible strategy** uses the existing `auto/upstream` route-mode framework and keeps Android physical-network-table mirroring off; it remains the default for generic and Xiaomi packages.
- **TierNest classic strategy** fixes the route mode to dedicated table `20110` and enables Android `rmnet_data*` / `wlan*` table mirroring; it is the default for the Ace 3 Pro package.
- Persist the selected strategy in `config/route-strategy.state`, preserve it across upgrades, clear runtime route-mode overrides on switch, and expose the strategy through status, metrics, and diagnostics.
- Bump the Ace profile revision to 9 and make the packaged metadata describe both selectable strategies instead of hard-coding one route mode.

## 0.5.0-beta.21 - 2026-09-01

- Restore the complete pre-beta.9 TierNest routing method for OnePlus Ace 3 Pro, not only its dedicated table: enable Android physical-network-table mirroring with `SYNC_ANDROID_NETWORK_TABLES=1` so fwmarked/bound application sockets receive EasyTier virtual/proxy routes in `rmnet_data*` / `wlan*` tables.
- Keep Xiaomi device packages on the post-beta.9 official-compatible `auto/upstream` path with Android table mirroring disabled.
- Disable the Ace TUN firewall guard by default after beta.20 packet counters proved both outbound and return traffic already crossed the TUN INPUT/OUTPUT hooks; retain the optional guard and diagnostics for future use.
- Bump the Ace profile revision to 8 and record Android network-table mirroring in the packaged profile metadata.

## 0.5.0-beta.20 - 2026-09-01

- Fix the recurring Ace 3 Pro state where EasyTier public transports and routes are connected, proxy ICMP works, but TCP/HTTP through the Root-created TUN fails while the same remote service is reachable locally and through the official APP.
- Add an Ace-only TUN firewall compatibility guard using dedicated `TN_ET_INPUT` / `TN_ET_OUTPUT` chains. It accepts local INPUT/OUTPUT only when both the managed TUN interface and an active EasyTier virtual/proxy CIDR match; ordinary Internet and unrelated interfaces are untouched.
- Reconcile the guard with route changes, remove it on stop/restart/uninstall, expose status and packet counters in diagnostics, and keep the generic module default off.
- Add regression tests for CIDR scoping, default-route exclusion, repair, and cleanup.

## 0.5.0-beta.19 - 2026-09-01

- Fix the beta.18 Ace 3 Pro package regression that wrote `ROUTE_MODE=auto` and ran as upstream/main instead of the beta.8/beta.12 verified dedicated table baseline.
- Restore `ROUTE_MODE=dedicated`, `ROUTE_AUTO_SWITCH_ENABLED=0`, table `20110`, and priority `9980` in the actual packaged Ace settings; set profile metadata to `route_mode=dedicated` and bump the Ace profile revision to 7.
- Fix transport-health classification so TCP `SYN_SENT` (`02`) and `CLOSE_WAIT` (`08`) no longer count as live transports. Only TCP `ESTABLISHED` (`01`) and connected UDP remote state (`07`) can suppress a reconnect restart.
- Add build-time assertions for the Ace route profile and expand recovery regression tests.
- Add the project-level `TierNest-故障与踩坑记录.md` maintenance reference covering confirmed Android routing, recovery, hotspot, packaging, shell, diagnostics, and release pitfalls.

## 0.5.0-beta.18 - 2026-09-01

- Fix the September 1 OnePlus failure where Wi-Fi lost DNS/TCP connectivity, Android switched from `wlan0` to mobile data, and the EasyTier process remained alive with zero transport endpoints and an unresponsive RPC portal.
- Track a physical-underlay signature (`dev`, gateway, source address, routing table) and restart EasyTier after a debounced Wi-Fi/mobile-data/default-network change, independently from external Android VPN changes.
- Add periodic EasyTier RPC health checks; repeated route-list timeout or invalid output now classifies the core as half-dead and triggers a cooldown-protected restart.
- Stop suppressing health recovery merely because the route list has no remote peers: reconnect waiting is allowed only when RPC is healthy and the core still owns live transport sockets. Zero endpoints or RPC timeout now restarts instead of waiting indefinitely.
- Treat the official EasyTier Android APP VPN as a dedicated conflict state. TierNest pauses without recording it as a generic external-VPN recovery, resumes automatically after the APP VPN closes, and preserves the original underlay/RPC failure evidence.
- Require the managed core to be running before identifying a TierNest TUN. A stopped core can no longer claim the official APP's same-IP `tun0`, and route synchronization now fails closed and removes TierNest route rules while the core is stopped.
- Add underlay/RPC/app-conflict status, counters, diagnostics, network snapshots, cleanup, and regression coverage.

## 0.5.0-beta.17 - 2026-08-31

- Reintroduce hotspot-client access as an opt-in **outbound-only** mode instead of restoring the old bidirectional/subnet-sharing behavior.
- NAT and FORWARD rules now match only active EasyTier virtual/proxy CIDRs that are currently routed through the EasyTier TUN; default routes and physical-interface routes are rejected fail-closed.
- Scope parent iptables hooks to the detected hotspot/TUN interface pair, use dedicated `TN_HS_OUT_NAT` / `TN_HS_OUT_FWD` chains, and install hooks only after child chains and policy rules are complete.
- Accept `ESTABLISHED,RELATED` replies from EasyTier and explicitly drop every other forwarded EasyTier-to-hotspot packet, preventing peers from initiating connections to hotspot clients even if later Android tethering chains are permissive.
- Do not advertise the hotspot subnet and refuse activation when it overlaps configured `proxy_networks`; no EasyTier-side route to hotspot clients is created.
- Stop changing global `ip_forward` and per-interface `rp_filter`; the mode observes Android hotspot forwarding state and fails safely instead of mutating shared sysctls.
- Restrict automatic interface detection to high-confidence Android hotspot interfaces, exclude generic `wlan*` uplinks, serialize rule updates with a stale-lock-safe lock, bound cleanup loops, and delete recorded policy rules only after exact ownership verification.
- Add an opt-in Settings card, status/error reporting, safe reapply, hotspot logs, diagnostics, metrics, migration of the new preference only, and regression tests for destination scoping, inbound blocking, repair, cleanup, proxy-network conflicts, and sysctl non-mutation.

## 0.5.0-beta.16 - 2026-08-31

- Remove TierNest's custom Android hotspot NAT, forwarding, policy-routing, periodic reconciliation, status controls, hotspot tab, and hotspot log UI.
- Keep only a cleanup-only legacy helper that removes old `TN_HS_NAT` / `TN_HS_FWD` chains, recorded hotspot policy rules, override/state files, and restores saved `rp_filter` / `ip_forward` values safely.
- Stop modifying Android tethering or ordinary hotspot Internet traffic. Computers connected to the phone hotspot now use the Android system network and their own Clash without TierNest interception.
- Reserve future hotspot integration for EasyTier's native `proxy_network` subnet-proxy mechanism rather than maintaining a second NAT implementation.

## 0.5.0-beta.15 - 2026-08-31

- Fix hotspot policy routing so TierNest only matches learned EasyTier virtual/proxy CIDRs instead of sending every tethered-client destination through the TierNest lookup table.
- Preserve ordinary hotspot Internet traffic for Android tethering and Clash/sing-box processing; TierNest now installs destination-specific `iif <hotspot> to <CIDR> lookup <table>` rules.
- Track every TierNest-owned hotspot rule as `priority|interface|CIDR|table`, verify/reconcile route changes, and delete only recorded TierNest rules during stop or uninstall.
- Fix shell-variable leakage from hotspot route discovery that could overwrite the detected hotspot CIDR.

## 0.5.0-beta.13 - 2026-08-31

- Add a persistent topology filter that can hide public relay/server nodes and display only EasyTier virtual nodes while preserving relay information through folded dashed links.
- Rebuild topology edges from the local route perspective: `DIRECT` links originate from the local node, virtual next hops connect through the matching virtual node, and public/unknown next hops are explicitly classified instead of being presented as direct links.
- Remove the fixed 28-node truncation and keep every virtual node plus the public next-hop nodes required to explain its active path.
- Add a complete virtual-node connection list below the map, showing hostname, virtual IP, configured location, coordinate state, connection type/path, exact next hop, hop count, latency, proxy CIDRs, and core version for every virtual node.
- Add an in-WebUI node-location editor with longitude/latitude range checks and atomic Base64 persistence to `node-locations.conf`; offline/unknown entries are preserved and the previous location file is backed up.
- Treat empty longitude/latitude as unset rather than `0,0`, keep unpositioned virtual nodes in an explicit unlocated layout, and restrict hostname-based geographic inference to public servers with an inference label.
- Make location saves transactional: backend failures keep the modal and in-memory topology unchanged, and both frontend/backend reject malformed delimiters or out-of-range coordinates.

## 0.5.0-beta.12 - 2026-08-31

- Fix the OnePlus Ace 3 Pro regression exposed by upgrading directly from beta.8: the Ace profile now restores the proven dedicated table `20110` / priority `9980` route baseline instead of starting from the newer upstream-main mode.
- Stop the health watchdog from repeatedly restarting EasyTier while the route list contains only the local node. EasyTier is now allowed to keep reconnecting to public peers, preventing the two-minute restart storm seen on mobile data.
- Keep Xiaomi profiles on the working KCP-off, smoltcp-off configuration; KCP was not the cause of the OnePlus transport-disconnected state.
- Fix shell variable pollution in transport snapshots that changed recovery reasons into nested strings such as `before-restart-health-*`.
- Remove a health-loop `continue` path and normalize recovery event formatting so route-mode repairs do not skip the watchdog sleep unexpectedly.
- Bump only the Ace 3 Pro profile revision to 5, resetting its recommended KCP-off config while preserving and backing up the previous configuration and auxiliary user state.

## 0.5.0-beta.11 - 2026-08-31

- Confirm the Xiaomi/HyperOS failure cause through device A/B testing: `enable_kcp_proxy = true` with the kernel TCP path can leave ICMP/Ping healthy while HTTP, SSH, and other TCP connections time out.
- Use the conservative Android defaults `dev_name = "tiernest0"`, `enable_kcp_proxy = false`, and `use_smoltcp = false` in the OnePlus Ace3 Pro, Xiaomi MiPad 5 Pro, and Xiaomi Mi10 device profiles. KCP and smoltcp remain user-selectable advanced options.
- Bump Xiaomi device profile revision to 4 so beta.10 automatic-`tunX` profiles migrate once to the verified stable defaults.
- Preserve node-location metadata, hotspot preference, existing backups, and a timestamped copy of the previous `config.toml` when a device-profile compatibility migration replaces the active configuration.
- Add visual WebUI controls and compatibility guidance for KCP TCP proxy and smoltcp, including a high-risk warning for KCP enabled without smoltcp.
- Preserve an intentionally empty `dev_name` in the WebUI instead of silently rewriting it to `tiernest0`; users can still choose automatic `tunX` allocation manually.
- Add TCP compatibility state, selected EasyTier TCP flags, and an optional best-effort TCP port probe to status, automatic snapshots, and exported diagnostics.
- Replace the provisional topology canvas with the bundled offline D3 Geo/world-atlas China/world map, bounded node placement, next-hop links, smart label collision avoidance, and reduced-motion behavior.
- Keep route/VPN/hotspot logic independent from the KCP setting, and retain complete uninstall cleanup without adding persistent system modifications.

## 0.5.0-beta.10 - 2026-08-30

- Match the EasyTier official Xiaomi behavior more closely by leaving `dev_name` empty in MiPad/Mi10 profiles so the core creates an automatic `tunX` interface instead of the custom `tiernest0` name.
- Exclude the EasyTier-owned automatic `tunX` from external VPN detection while continuing to detect separate Clash/WireGuard/PPP/Meta interfaces.
- Bump Xiaomi device profile revision to 3 so upgrades replace older fixed-`tiernest0` configurations once.
- Rebuild the topology visualization as an offline China/world map with bounded geographic placement, an unknown/public relay band, next-hop edges, and optional longitude/latitude fields in `node-locations.conf`.
- Fix the topology pile-up bug by separating the SVG positioning transform from the animated child group; node animation can no longer overwrite map coordinates.
- Replace continuous force simulation with a deterministic map layout and a 180 ms one-shot entry transition, including reduced-motion behavior.

## 0.5.0-beta.9 - 2026-08-30

- Re-audit EasyTier v2.6.4 official Magisk module and preserve its proven `from all lookup main` behavior as an upstream-compatible route mode.
- Add automatic route modes that always start with the proven upstream `from all lookup main` behavior, then promote to destination-specific `target-main` and finally `dedicated` only when connectivity probes show the current ROM/VPN needs it.
- Add automatic route-mode fallback when forced-TUN connectivity works but normal proxy routing fails, with a switch cooldown to avoid oscillation.
- Reconcile the active route mode every 30 seconds and clear runtime overrides on external VPN changes, fixing the official module weakness where netd/Clash could delete a rule while the still-running core caused the official loop to skip route repair.
- Reorder health classification so blocked public ICMP does not hide an EasyTier routing failure when forced-TUN probes still work.
- Use the active mode's lookup table for hotspot forwarding and detect hotspot conflicts from cached EasyTier CIDRs rather than all routes in `main`.
- Remove the static `tcp://192.168.50.1:11011` peer from device configs to prevent circular attempts through the same OpenWrt proxy while away from home.
- Bump Xiaomi device profile revision so upgrading replaces beta.8 configs containing the deprecated local-LAN peer.
- Keep Android-network-table mirroring disabled by default; beta.9 no longer relies on the unsuccessful beta.8 Xiaomi workaround.

## 0.5.0-beta.8 - 2026-08-30

- Confirm with an OpenWrt counter-only diagnostic rule that Xiaomi browser TCP 80/443 traffic never reaches EasyTier even though Root probes and reverse pings succeed.
- Discover active Android physical network tables from netd policy rules, such as `lookup wlan0` for fwmarked application sockets.
- Mirror EasyTier overlay and proxy CIDRs into those active Android network tables while keeping public/default traffic unchanged.
- Track mirrored routes as `table|CIDR|device`, repair netd deletions during periodic reconciliation, and remove only TierNest-owned entries on stop/uninstall.
- Expose Android app route/table counts in status, metrics, diagnostics, and the WebUI route summary.
- Add regression coverage for wlan0-table installation, netd route deletion recovery, and cleanup.

## 0.5.0-beta.7 - 2026-08-30

- Add runtime route-table capability detection for older Android `ip` tools that reject large table IDs such as 20110.
- Keep table 20110 on supported systems and automatically select an unused low table starting at 110 on Android 13/legacy iproute implementations.
- Persist requested/effective table selection, expose both in diagnostics, and clean both during uninstall.
- Add device-profile identity checks (`expected_hostname` and `expected_ipv4`) so a Mi10/Pad package replaces a valid-looking config copied from another phone instead of preserving a duplicate virtual IP.
- Add a regression test reproducing Mi10 preserving `Example-Phone-A / 10.42.0.10` and proving automatic replacement with `Example-Phone-B / 10.42.0.52`.
- Add a Magisk automatic diagnostic build that writes a redacted report to Download without requiring terminal `su` commands.

## 0.5.0-beta.6 - 2026-08-30

- Detect directly connected physical IPv4 subnets on Wi-Fi, Ethernet, mobile, USB, Bluetooth, bridge, and hotspot interfaces while excluding EasyTier and external VPN tunnel interfaces.
- Mirror local connected subnets into table 20110 so home-LAN traffic remains direct even when OpenWrt advertises the same CIDR through EasyTier.
- Prefer a covering physical subnet over an overlapping cached EasyTier proxy route; automatically restore the EasyTier route after leaving the local LAN.
- Reconcile route specifications as `CIDR|device`, fixing wrong-device routes instead of comparing only destination prefixes.
- Delete stale TierNest-owned route-table entries that are no longer in the expected specification set.
- Expose local direct-route override counts in status, metrics, diagnostics, and the WebUI route summary.
- Add regression coverage for same-CIDR OpenWrt proxy overlap, home departure, home return, and cleanup.

## 0.5.0-beta.5 - 2026-08-30

- Add a privacy-safe EasyTier IPv4 transport endpoint observer using process-owned socket inodes and route decisions.
- Record before/after endpoint snapshots around automatic VPN or health recovery restarts.
- Add structured diagnostics schema v2 with recovery timing, binary identity, route decisions, TUN/sysctl state, hotspot state, and redacted logs.
- Make exported diagnostics include the structured report and transport history while continuing to exclude the full EasyTier core log.
- Replace hard-coded personal diagnostic targets with configured health targets or the first host of the configured EasyTier subnet.
- Pause all WebUI shell-backed polling while the KernelSU WebView is hidden and refresh immediately when it returns to the foreground.
- Keep KernelSU desktop shortcut metadata for both the WebUI and the diagnostic action.
- Clean transport observer state during uninstall and add regression coverage for redaction, endpoint decoding, WebUI visibility polling, and cleanup.

## 0.5.0-beta.4 - 2026-08-29

- Make uninstall cleanup race-free: mark removal, stop and wait for the daemon, stop the watcher, then perform final idempotent core/route/iptables/sysctl cleanup.
- Add atomic daemon and network-watcher lock directories with stale-lock recovery to prevent duplicate background loops.
- Save and restore hotspot-interface and EasyTier-TUN `rp_filter` values.
- Track a TierNest-induced IPv4 forwarding 0→1 transition and restore it only after Android hotspot disappears; never disable forwarding while active tethering still needs it.
- Roll back partial hotspot iptables/sysctl mutations when rule application fails.
- Track whether TierNest disabled the legacy `easytier_magisk` module and restore only that TierNest-owned state during uninstall.
- Add an uninstall simulation proving no custom policy rules, table routes, iptables jumps/chains, process/lock files, or modified rp_filter values remain.
- Add daemon/watcher duplicate-start lock tests.
- Cache the resolved iptables path, avoid filesystem temp files during hotspot scanning, and support additional bridge-style AP interface names.
- Reduce recurring work with 10-second network watch, 15-second hotspot verification, lazy WebUI config loading, disabled-hotspot iptables skip, and 60-second EasyTier route-discovery cache while preserving 30-second table reconciliation.
- Keep all beta.3 SVG sizing and beta.2 version-badge fixes.

## 0.5.0-beta.3 - 2026-08-29

- Fix oversized Overview heartbeat, service-control gear, and hotspot-control lightning SVGs on Android WebView.
- Add explicit `width="18" height="18"` attributes and a dedicated `section-title-icon` class to every section heading icon.
- Add final `!important` min/max width, height, and flex-basis constraints so later theme rules cannot restore intrinsic SVG sizes.
- Add a Chrome regression assertion that all visible section icons stay at or below 20×20 px and no visible tab SVG exceeds 64 px.
- Include all beta.2 version-badge and background-overhead optimizations.

## 0.5.0-beta.2 - 2026-08-29

- Fix the first-open version badge flash where KernelSU `moduleInfo()` JSON metadata was rendered as a huge blue label before status refresh.
- Parse object, JSON-string, and semver inputs into a compact label such as `v0.5.0 β2`.
- Hard-limit the version badge to one line with max-width and ellipsis, including 320px narrow-screen tuning.
- Improve header flex shrinking, long VPN/interface/CIDR truncation with title hints, four-tab navigation sizing, disabled-button protection, and touch feedback through the Herdr `agy` UI review.
- Reduce background diagnostic polling: network signature interval 5→10 seconds and hotspot rule verification 10→15 seconds.
- Lazy-load private EasyTier configuration only when the Settings tab is opened.
- Skip iptables polling entirely when hotspot forwarding is disabled and already clean.
- Cache the iptables binary path, avoid repeated identical subnet-conflict logs, and use more portable `ip addr show` + link-state detection for BusyBox/Android compatibility.
- Add hotspot subnet overlap protection and show an explicit WebUI conflict state.
- Keep all v0.5.0-beta.1 NAT hotspot forwarding features.

## 0.5.0-beta.1 - 2026-08-29

- Add NAT-mode Android hotspot forwarding so devices connected to the phone hotspot can access EasyTier peers and remote proxy CIDRs without installing EasyTier.
- Auto-detect common Android hotspot interfaces (`ap0`, `swlan0`, `softap0`, non-uplink `wlan*`) and their private IPv4 subnet.
- Add dedicated `TN_HS_NAT` and `TN_HS_FWD` iptables chains with idempotent install, verification, repair, and cleanup.
- Add a hotspot ingress policy rule (`iif <hotspot> lookup 20110`) before Android VPN/tethering rules while preserving the global phone-originated rule.
- Keep normal hotspot Internet traffic on Android tethering/VPN because table `20110` contains only EasyTier and learned proxy routes.
- Add periodic hotspot interface/rule monitoring, Android/netd rule repair, connected-client count, state persistence, metrics, diagnostics, and safe logs.
- Enable hotspot NAT by default only in the device-specific private package; the public generic package defaults to off.
- Add a fourth Herdr/agy-designed WebUI tab for hotspot status, NAT explanation, clients, interface/CIDR/gateway/TUN, rule priority, reapply count, last apply time, and start/stop/auto/reapply controls.
- Add hotspot logs to the WebUI log selector and safe diagnostic exports.

## 0.4.0-beta.2 - 2026-08-29

- Preserve unknown EasyTier TOML keys, flags, sections, arrays, and `[[peer]]` entries when saving through the visual editor by using `smol-toml` end-to-end.
- Add a real headless-Chrome integration test with a mocked KernelSU bridge covering metrics, tabs, config validation/save/backup/restart, logs, and export.
- Supersede `0.4.0-beta.1`, whose final frontend review temporarily restored the legacy serializer and could drop advanced fields during visual save.
- Keep the complete route-table reconciliation and device-specific private health watchdog introduced during the beta.1 development cycle.

## 0.4.0-beta.1 - 2026-08-29

- Redesign the KernelSU WebUI with the right-side Herdr `agy` agent.
- Add Overview, EasyTier Settings, and Logs tabs with a mobile-first layout.
- Add CPU, RSS/VM, threads, file descriptors, runtime, TUN traffic, log size, route sync, and recovery metrics.
- Add visual editing for EasyTier identity, IPv4/DHCP, listeners, peers, MTU, RPC portal, encryption, IPv6, P2P, bind-device, private mode, exit node, and hole-punch settings.
- Add an advanced TOML editor backed by `smol-toml`, preserving unknown fields and arrays-of-tables.
- Add server-side Base64 config read, validation, atomic save, timestamped backups, and save-and-restart flows.
- Preserve edited configurations and backups across private-package upgrades.
- Reconcile the complete dedicated route table instead of checking only whether one route remains.
- Retain previously learned proxy CIDRs across transient EasyTier advertisement loss until a core restart.
- Add a device-specific private health watchdog: repair route drift first, then restart EasyTier after repeated overlay/proxy failure while Internet remains available.
- Add KernelSU WebUI status warnings for `command_args` mode and disable TOML save actions in that mode.

## 0.3.0-beta.1 - 2026-08-29

- Add a KernelSU WebUI built with the official `kernelsu` JavaScript bridge.
- Display service state, PID, TUN, external VPN, policy table, network name, and virtual IPv4.
- Add WebUI controls for start, stop, restart, route synchronization, and safe log export.
- Add recent runtime/network log viewers with automatic status refresh.
- Add a local module icon for WebUI and Action entries.
- Keep the module Action button as a fallback one-click log export.
- Stop recursively changing `webroot` permissions so KernelSU can assign the required SELinux context.
- Bundle the WebUI offline with no external runtime network dependency.

## 0.2.0-beta.1 - 2026-08-29

- Promote the Android 16/KernelSU implementation to the first beta release.
- Keep automatic EasyTier restart when an external Android VPN interface appears or disappears.
- Wait four seconds for Android VPN routing to settle before rebuilding EasyTier connections.
- Keep the dedicated policy table `20110` and automatic proxy-CIDR synchronization.
- Reject the untouched empty example configuration instead of starting a useless network.
- Exclude Android's `tunl0` IP-in-IP interface from EasyTier TUN detection.
- Reduce unchanged-state full diagnostic snapshots from 60 seconds to 300 seconds.
- Keep event-triggered snapshots and KernelSU one-click safe log export.
- Keep private-package support that prefers the embedded configuration over stale installed files.

## 0.1.0-alpha.3-recover1 - 2026-08-29

- Automatically restart EasyTier when an external VPN interface appears or disappears.
- Verified recovery in about 14–20 seconds on Android 16 with `com.follow.clash`.

## 0.1.0-alpha.2-diag1 - 2026-08-29

- Add automatic network snapshots, connectivity probes, and one-click diagnostic export.
- Add private embedded-configuration packages.

## 0.1.0-alpha.1 - 2026-08-28

- Initial KernelSU-first module and Android 16 policy-routing experiment.
