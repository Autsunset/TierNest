# TierNest

独立 Android EasyTier 组网 App，提供可选 **VPN / Root 模式**、原生 Compose 界面、
节点拓扑、TOML 配置与 Download 备份。保留 Magisk / KernelSU / APatch 通用模块。
TierNest 是社区项目，与 EasyTier 上游没有官方隶属关系。

- **App：0.2.0-alpha07**，Android 8+，VPN 支持 arm64 / x86_64，Root 支持 arm64。
- **模块：1.1.0**，所有 arm64 设备使用同一个通用 ZIP；EasyTier 核心均为 2.6.4。
- [下载 APK](https://github.com/Autsunset/TierNest/releases) · [App 使用与构建](android/README.md) · [验证记录](android/PLAN.zh-CN.md)

## Android App

首页可自由选择无需 Root 的系统 VPN，或让出 VPN 槽位的 Root 组网。
VPN 模式会占用 Android VPN 槽位；Root 与 Clash 的实际共存还受系统路由和防火墙限制。
新安装默认 VPN，老安装保留 Root；切换时保留配置并先断开。

提供星际控制台、MD3、Miuix 澎湃三种外观与明暗设置。概览显示流量、连接时长与
路由状态，节点页支持实际路由拓扑和节点详情，配置页支持分组表单与原始 TOML。
停止会退出服务，后台按需维护；真实设备功耗与 Root/Clash 共存仍需完整实测。

```sh
./scripts/build-android.sh
```

构建需要 Android SDK/NDK、JDK 与 Rust，详见 [App 文档](android/README.md)。
原模块迁移会先完整备份，对参数、路由和热点能力不等价的部分要求明确选择。

## 通用 Root 模块

模块的发布入口、版本来源和无损升级政策继续独立保留。以下为模块版本记录。

## v1.1.0：可选事件检测与自定义间隔

在“概览 → 运行方式 → 自动检测方式”选择方式，点击“保存检测设置”。已有用户保持定时检测、30 秒间隔；不会在升级时自动改为事件检测。

- **定时检测**：间隔可输入正整数秒，例如 30、60、300。每次检查网关身份和经 Wi-Fi 的 HTTP 连通性；同一网络连续两次验证失败后恢复手机核心。间隔从上次检查完成后开始计时。
- **事件检测**：先按原流程验证并保存网络。启动自动模式时判断一次，之后监听 Wi-Fi 连接、断开、漫游和网络配置变化，匹配已保存的网关 IP/MAC；不定时扫描、不重复 HTTP 验证。网络变化后合并通知并在几秒内有限补查，处理地址、路由和邻居表尚未就绪的情况。必要时只向本地网关发一次探测以读取 MAC。
- 事件检测信任首次验证的网络：Wi-Fi 保持连接但路由器代理故障时，不会自动恢复手机核心。需要持续验证时选择定时检测。事件检测不支持的设备会拒绝保存此选项；监听器意外退出时恢复手机核心并在界面显示错误，不自动切回轮询。
- 检测方式与间隔独立保存；切回定时检测会保留之前的间隔。运行中保存会替换检测进程，手动停止后保存只更新偏好，不能启动服务。重启和升级均继承设置。

以下版本章节记录历史行为；当前自动检测以本节为准。

## v1.0.6：修复自动模式和开机脚本权限

修复安装后应用自动模式报“操作失败”的问题：Root 管理器可能重置 ZIP 文件权限，安装器此前漏给自动检测和开机入口脚本设置执行权限。现在覆盖全部根目录 Shell 脚本，新增安装权限回归检查。配置、多网络记录、运行方式和手动停止状态继续继承，检测间隔仍为 30 秒。

## v1.0.5：记住多个可代理网络

自动模式支持同时记住家庭路由器、随身 Wi-Fi 等多个网络。连接其中任意一个已记住的网关，且经该 Wi-Fi 能访问指定虚拟地址时，手机核心进入“自动待机”；离开这些网络或代理失效时恢复。

- “概览 → 运行方式 → 记住可代理的 Wi-Fi”：连接要添加的网络，填写虚拟网络验证地址及 HTTP 端口，验证并保存。网关 IP、MAC、WLAN 接口自动读取；保存新网络保留已有记录，同一网关重复保存更新验证目标。
- 已保存列表显示网关、MAC、验证地址和当前代理状态，每条可单独移除。移除最后一条时回到手动模式；先前的手动停止状态仍保留。
- 两个已记住且可用的路由器之间切换继续待机。切到不同网关且代理失效时立即恢复；当前同一网关连续两次探测失败时恢复，保留抗瞬时丢包处理。
- 仍使用每 30 秒一次的检查，先匹配网关身份，再强制通过 WLAN 验证虚拟网络访问。手机自己的 EasyTier 或其他 VPN 不作为路由器代理可用的依据。
- v1.0.4 的单网络记录无需改写即可读取，新增记录时转为多记录格式。升级逐字节继承整个记录文件、运行方式及停止状态，通用 ZIP 不包含私人网关信息。

## v1.0.4：可选手动 / 自动运行方式

概览的“运行方式”提供两个选项，升级默认保持手动模式，不自动替用户启用家庭识别。

- 手动模式：自行启动和停止。停止会退出核心、守护、网络监视及其子进程，清理模块路由；配置保留，重启手机后仍保持停止。WebUI 在手动停止时也暂停定时状态/日志读取，可手动刷新。
- 自动模式：连接家庭 Wi-Fi 时，填写 OpenWrt 的虚拟 IPv4 和 HTTP 端口，点击“验证并记住当前家庭 Wi-Fi”，再应用自动模式。以物理 WLAN 接口、网关 IP/MAC 和强制走 WLAN 的虚拟网络 HTTP 探测判断，避免手机自己的 EasyTier 或 VPN 让探测误成功。
- 在家待机时仅保留每 30 秒检查一次的家庭监视；核心、普通守护和网络快照任务退出。离家后恢复；同一家庭网关连续两次探测失败也恢复，避免 OpenWrt 组网中断后手机失联。识别及恢复有约 30–60 秒检测延迟，核心启动还需要几秒。
- 自动模式下点击停止同样关闭全部后台，自动检测、切换模式和重启手机都不会撤销手动停止；点击启动/重启才解除。路由策略和热点设置也不会擅自解除停止。
- 升级逐字节继承 `service-mode.state`、`home-network.conf`，通用包不包含任何家庭网关或个人虚拟地址。更换路由器或网关 MAC 后重新记住家庭 Wi-Fi。系统须有 curl，HTTP 端口须可经家庭网关访问。

## v1.0.3：Download 配置备份与自动迁移

配置的手动备份、保存前自动备份现在写入 `/sdcard/Download/TierNest/backups/`，WebUI 显示完整保存路径。普通新备份保留最近 10 份。

升级后首次打开设置、创建备份或保存配置时，会将旧 `config/backups/`（包括升级快照）整体迁入唯一的 `legacy-时间-进程-序号/` 子目录。所有文件逐字节校验通过后才清理原目录；已存在的 Download 文件不覆盖，迁入的历史目录不参与 10 份新备份清理。手机未解锁或 Download 不可写时保留旧备份，下次配置操作重试；配置读取仍可用，保存操作在备份失败时不会替换当前配置。迁移不增加后台轮询。

## v1.0.2：一个安装包，自动继承配置

正式发布统一为 `TierNest-v1.0.6-et2.6.4-arm64.zip`。小米 10、小米平板、一加等 arm64 设备使用同一个 ZIP，兼容 Magisk、KernelSU 和 APatch。

- **直接覆盖升级，先不要卸载旧模块**：安装时逐字节保留已有 `config.toml`、命令参数、节点与密钥、路由/热点偏好、手动停止状态和历史备份。
- 保留已有 `settings.conf` 中新版仍支持的参数，新增加的参数采用新版默认值。旧专用包的路由策略继续保留。
- 安装前在新模块的 `config/backups/upgrade-时间-序号/` 中备份旧配置、运行参数和旧设备元数据。复制或合并失败会中止安装，不继续禁用旧模块。
- 设备型号、hostname、IP 和旧 `profile_revision` 不再触发内置配置覆盖。首次安装才使用空白模板，需要在 WebUI 配置组网。
- 本版包含 v1.0.1 的完整网络快照重复采样修复。升级会保留原节点配置，连接失败的节点仍需单独检查；续航改善需要拔线待机实测。

后续只使用 `scripts/build-module.sh` 构建。旧私密/机型构建入口不再接受配置文件或设备标签，也不再生成其他变体。版本号统一读取 `module/module.prop`。

## v1.0.1：VPN 恢复与后台采样修复

- VPN 接管默认路由时，通过 Android 默认物理网络表识别实际上联，避免把 FlClash 的 `tun0` 当作 Wi-Fi/移动数据切换；同时发生的上联/VPN 变化只重启一次。
- VPN 防抖、冷却和失败重试保留待处理状态；停止、禁用和官方 APP VPN 优先于恢复。
- 修复传输采样的 Shell 变量污染，稳定网络恢复为默认每 5 分钟完整采样一次；修复 `/32` 主机路由比较导致的重复删除/重写。
- 网络监测脚本可拉起意外退出的主守护进程；WebUI 启动也检查守护进程。手动停止/禁用/卸载及官方 APP VPN 均阻止拉起。
- 诊断新增守护进程 PID、心跳、停止标记、等待位置和恢复阶段。对仍存活但卡住的守护进程只记录，不自动强杀。

v1.0.1 的历史发布保留了设备专用包；从 v1.0.2 起使用上面的统一升级流程。升级后仍需真机验证 Clash 开关、移动数据与家庭 Wi-Fi 切换及待机续航。

## v1.0.0：可靠性与采样优化

- 修复物理网络连续切换、防抖期间再次变化以及冷却期内变化被误判为“已处理”：观察状态与成功恢复状态分离，失败重连保留待处理事件；手动停止、禁用模块和官方 APP VPN 优先。
- 配置写入使用带进程所有权的互斥锁，备份文件名唯一且禁止覆盖，同秒/并发保存保留各次前置配置；继续原子替换配置文件，最多保留 10 份正常配置备份。
- 概览使用单一 `control.sh overview` 快照（`schema=1`、`status.*`、`metrics.*`），共享本轮 RPC、上联和端点采样。原 `status` / `metrics` 接口保留兼容；守护进程仍直接读取实时探测，不使用 UI 缓存做恢复判断。
- 相同读取请求合并，旧目标/旧页面会话的响应丢弃；切换日志、切回前台和服务操作后的刷新不会被旧响应覆盖。日志保留一个 5 秒轮询入口，后台暂停。
- 热点操作失败先回退到最后确认值，再释放忙碌状态重新读取；读取也失败时明确显示“状态未确认”。
- 日志搜索按字面匹配，在原始文本上计算高亮后转义输出，搜索 `INFO`、`a+b` 或 HTML 字符不会破坏生成的标签。
- 模块磁盘大小缓存 5 分钟，升级或时钟回拨时失效；运行状态、流量和恢复探测不使用这个低频缓存。

### 从 beta.24 升级

选择设备对应的完整 ZIP，在原 KernelSU/Magisk 模块管理器中覆盖升级。模块 ID、核心版本、设备网络身份和 profile revision 不变，已有有效配置、备份和路由策略继续按原规则保留。Ace 3 Pro 默认经典策略，小米设备默认官方兼容策略；不以升大版本为由覆盖用户已选择的方案。

本次自动化验证不代替三台 Android 真机升级后的 Wi-Fi/移动数据、普通应用 TCP、VPN 与热点测试。安装包含私人密钥时不可公开分享。

## 名称

暂定名称：**TierNest**。

- 模块：TierNest Core
- 未来管理端：TierNest App
- 模块 ID：`tiernest`
- 默认 TUN：`tiernest0`

名称取意为“虚拟网络节点的巢/控制中心”。在 2026-08-28 的初步公开检索中未发现同名的
主流 Android 网络工具，但正式发布前仍应进行商标、应用商店和域名复核。

## 为什么不是 LSPosed

Android 同一用户配置只能保持一个活动的 `VpnService`。TierNest 不创建 Android
`VpnService`，而是由 Root 后台直接运行 EasyTier 原生核心并维护 TUN/策略路由，因此可以
把系统的 VPN 槽位留给 Clash、sing-box、WireGuard 等应用。

## Android 16 修复策略

上游 v2.6.4 的 Magisk 模块只补充了一个通用 `lookup main` 规则。Android 16 与部分厂商
ROM 的策略路由会在 `main` 表之前进入按网络/VPN 划分的路由表，导致 EasyTier 进程在线、
TUN 存在，但虚拟网段不通。

TierNest 使用独立路由表解决：

1. 自动识别 EasyTier TUN 和虚拟网段；
2. 从 EasyTier RPC 同步虚拟节点及代理网段；
3. 将这些网段写入专用表 `20110`；
4. 添加一条高优先级规则查询专用表；
5. 专用表没有匹配时继续执行 Android 原有规则，所以不会接管普通流量；
6. 默认忽略 `0.0.0.0/0`、两个 `/1` 等出口节点路由，避免抢占另一个 VPN。

## 构建

本地仓库保留源代码、通用空白配置和合成测试数据；文档中的网络地址与设备名均为示例。私人配置、诊断截图、运行数据、依赖和发布 ZIP 不纳入 Git。首次构建会安装 WebUI 依赖，并下载和校验所需的上游核心二进制。

构建 Wi-Fi 事件监听器需要 Android NDK（设置 `ANDROID_NDK_HOME`，或安装在 Android SDK 的 `ndk/` 目录）。它生成通用 arm64 Android 程序，无需安装额外 App。原生事件解析测试在 Linux 主机运行，需 `cc`；其他平台构建时会明确提示此项需在 Linux 补测。

```bash
./scripts/build-module.sh
```

产物位于 `dist/`。构建脚本会下载 EasyTier 官方 `v2.6.4` Magisk 包，只提取其中的
`easytier-core` 和 `easytier-cli`，并校验 SHA-256。

## 安装

1. 在 Magisk、KernelSU 或 APatch 管理器中覆盖安装 `dist/TierNest-v1.1.0-et2.6.4-arm64.zip`；
2. 安装器会优先迁移旧模块的 `config.toml`/`command_args`；
3. 旧的 `easytier_magisk` 会被禁用，避免重复启动；
4. 重启手机；
5. KernelSU 模块页面的“操作”按钮会导出安全诊断日志到 Download 目录；
6. KernelSU 3.1.0 及以上可在模块卡片点击“＋”，选择 **WebUI** 创建 TierNest 桌面快捷方式。

控制接口（也供未来管理 App 调用）：

```bash
su -c '/data/adb/modules/tiernest/control.sh status'
su -c '/data/adb/modules/tiernest/control.sh restart'
su -c '/data/adb/modules/tiernest/control.sh sync-routes'
```

配置：

```text
/data/adb/modules/tiernest/config/config.toml
```

## 诊断

```bash
su -c /data/adb/modules/tiernest/diagnose.sh
```

命令会生成结构化诊断报告 v2，并自动隐藏 `network_secret`、命令行密钥和 URL 用户信息。报告包含恢复原因/耗时、传输端点、策略路由、TUN、热点、sysctl、节点与重要错误：

```text
/data/adb/modules/tiernest/logs/diagnostics-*.txt
```

常用检查：

```bash
su -c 'pgrep -af easytier'
su -c 'ip -4 rule show'
su -c 'ip -4 route show table 20110'
su -c 'tail -n 100 /data/adb/modules/tiernest/logs/tiernest.log'
su -c 'tail -n 100 /data/adb/modules/tiernest/logs/easytier.log'
```

## KernelSU WebUI

`v1.0.0` 提供三页移动端 WebUI：

- **概览**：状态、PID、TUN、外部 VPN、路由、CPU、RSS/VM、线程、FD、运行时长、TUN 流量、日志占用、VPN/健康恢复次数；
- **EasyTier 设置**：可视化编辑身份、IPv4/DHCP、网络名与密钥、listeners、peers、MTU、RPC portal 和常用 flags，并提供完整 TOML 编辑器；
- **日志**：运行、网络和传输端点日志切换、搜索、行数选择、自动刷新、复制和跳到底部。

配置通过 UTF-8 Base64 传给固定后端命令，服务端使用 EasyTier 自身校验器验证，通过后先向 Download/TierNest/backups 创建旧配置备份，再原子保存新配置。统一包升级会保留用户在 WebUI 中编辑的配置和备份。原模块“操作”按钮仍保留为一键导出日志备用入口。

概览页的“组网拓扑”从 `v0.5.0-beta.24` 起改为**本机路由拓扑树**，不再使用地图、经纬度或城市推断。节点卡片显示名称、虚拟 IP、连接方式和路径延迟；直连节点挂在本机下面，二跳节点挂到对应的公网中继或虚拟下一跳，代理网段挂到发布网关。

- **实线**表示已知路由连接；**虚线**表示折叠中继、未展开的多跳或未确认路径。`next_hop` 是从本机出发的第一跳，超过两跳时不能假装它与目标直接相连。
- 未上报的下一跳使用明确标记的占位节点，不计入在线/已上报节点数量；缺失、冲突或环路数据不会凭空生成直连。
- “仅虚拟节点”隐藏公网节点并将路径折叠为虚线，详情保留具体中继名称。
- 紧凑的纵向树在手机上不需要横向缩小文字，上下滚动即可查看所有分支；点击节点高亮路径。刷新保留选中状态和滚动位置。
- 这是本机当前路由视角，不是全网完整物理链路图。旧 `node-locations.conf` 和后端读写接口仅保留供兼容/回退，不再由 WebUI 请求或影响布局。

WebUI 在退到后台或通过桌面快捷方式切换到其他应用后，会完全暂停状态与日志的 shell 轮询；返回前台时立即刷新，避免隐藏 WebView 持续调用 KernelSU bridge。

### KernelSU 桌面快捷方式

TierNest 已在 `module.prop` 中提供 `webuiIcon` 和 `actionIcon`。在支持模块快捷方式的 KernelSU 管理器中，进入模块页并点击 TierNest 卡片上的“＋”：

- 选择 **WebUI**：桌面图标直接打开 TierNest 管理页面；
- 选择 **模块操作**：一键导出脱敏诊断报告，不会打开管理页面。

快捷方式由 KernelSU 管理器承载，不额外安装 APK，也不会占用 Android VPN 槽位。

## 自适应路由模式

`v0.5.0-beta.13` 保留三种路由实现，并按已验证设备基线选择起点：小米与通用配置使用 EasyTier 官方的 `from all lookup main`，Ace 3 Pro 专用包恢复 beta.8 已验证的独立表 `20110`：

- **upstream**：小米与通用配置的默认模式；模块每 30 秒、核心重启和 VPN变化后都会重新确认该规则存在，修复官方模块“核心仍运行就跳过路由检查”的长期失效问题；
- **target-main**：强制 TUN 可达但普通代理路由失败时，自动为每个 EasyTier CIDR 添加高优先级 `to <CIDR> lookup main`；
- **dedicated**：前两种仍失败时使用独立表，只接管 EasyTier CIDR；
- **auto**：按上述顺序切换，并设置冷却时间避免循环震荡；Ace 3 Pro 专用包固定使用已验证的 dedicated 基线，不参与自动切换。

Clash 等 VPN 开启或关闭时，小米/通用 auto 配置会恢复上游兼容模式重新检测；Ace 3 Pro 则重建其专用表规则。普通公网流量和默认路由不由 TierNest 接管；只有检测到实际故障才升级路由强度。

设备回家连接与 OpenWrt proxy 相同的局域网时，upstream/target-main 由 main 表的直连路由优先，dedicated 模式使用本地直连覆盖。随身 WiFi 只要使用唯一 EasyTier IP并发布自己的 LAN CIDR，也不会与手机自身 EasyTier 冲突。

## TUN 设备命名与自动 tunX 兼容

所有正式设备配置统一使用已验证稳定的 `dev_name = "tiernest0"`。Android 正式配置默认关闭发送端 KCP TCP 代理并保持 `use_smoltcp = false`，避免部分 HyperOS/定制内核出现“Ping 正常但 HTTP/SSH 等 TCP 超时”。同时，模块运行时完全兼容用户手动在 WebUI/配置中将 `dev_name` 留空产生的 `tunX` 自动接口分配行为：模块通过配置的虚拟 IP 智能识别 EasyTier 实际接口，并从外部 VPN 检测中排除该接口，因此即使使用 EasyTier `tunX` 也能与 Clash 的另一条 `tunX` 清晰区分并稳定共存。

## KCP 与 smoltcp 兼容选项

`v0.5.0-beta.13` 已将 `enable_kcp_proxy` 和 `use_smoltcp` 加入 WebUI 可视化设置：

- **推荐稳定模式**：`enable_kcp_proxy = false`、`use_smoltcp = false`。普通 EasyTier 三层组网、子网访问、外部 VPN 共存和热点共享不依赖发送端 KCP。
- **KCP 内核模式（高风险）**：`enable_kcp_proxy = true`、`use_smoltcp = false`。它会截获并包装 EasyTier TCP；部分小米/HyperOS/定制内核可能只剩 Ping 可用，而 HTTP、SSH 等 TCP 超时。
- **KCP 兼容模式**：两项同时开启。EasyTier 的代理/KCP TCP 路径改用用户态 smoltcp，可绕开部分内核兼容问题，但会增加少量 CPU 与内存开销。

`use_smoltcp` 只影响 EasyTier 自身的代理/KCP TCP 路径，不会接管整台 Android 设备的全部 TCP。模块在启动日志、状态和导出诊断中记录当前组合；设备私密包还会对 `192.168.50.1:80` 执行尽力而为的 TCP 连通性探测。探测工具不可用时只显示 `UNAVAILABLE`，不会改变配置或反复重启核心。

## Android 13 / 旧版 iproute 路由表兼容

部分 Android 13 ROM 的系统 `ip` 命令不接受 `table 20110`，会报 `invalid argument '20110' to 'table ID'`。`v0.5.0-beta.13` 会先探测请求表号：支持时继续使用 20110；不支持时从 110 开始选择未被 Android 规则占用的低位表号，并把选择写入 `run/route-table-selection`。

WebUI 和诊断中的 `route_table` 表示实际使用的表号，`requested_route_table` 表示配置请求的 20110。卸载时会同时清理实际表和请求表，不留下回退规则。

## 家庭局域网与 OpenWrt 网对网重叠保护

OpenWrt 发布 `192.168.50.0/24` 时，设备在外网会通过 EasyTier 访问家庭局域网；设备回到家并连接同一个 `192.168.50.0/24` Wi-Fi 后，这条代理路由与 `wlan0` 的直连路由发生重叠。

`v0.5.0-beta.13` 会检测 Wi-Fi、以太网、移动网络、USB、蓝牙、bridge 和热点接口的直接连接网段，并把本地直连路由镜像到表 `20110`：

- 在家：`192.168.50.0/24 dev wlan0`，OpenWrt、NAS 和本地 Peer 直接访问；
- 离家：本地网段消失，自动恢复 `192.168.50.0/24 dev tiernest0`；
- 返回家：再次切换为 `wlan0`，不需要重启或手动改配置；
- 外部 VPN 的 `tun`/`wg`/`ppp` 接口不会被误识别为本地局域网。

WebUI 路由卡片会显示 `本地直连 N`，诊断报告的 `Local direct-route overrides` 部分会列出当前覆盖关系。可通过 `settings.conf` 的 `PREFER_DIRECT_LOCAL_SUBNETS=0` 关闭，但不建议在存在同网段 OpenWrt proxy 时关闭。

## VPN 切换自动恢复

`v0.5.0-beta.13` 会检测外部 `tun0`/WireGuard/PPP 等 VPN 接口的出现与消失。
状态变化后等待 4 秒，让 Android 路由稳定，然后自动重启 EasyTier 并恢复表 `20110`，
减少 VPN 开关后约一分钟的 EasyTier 数据面中断。

## 物理网络切换与半失效核心恢复

`v0.5.0-beta.22` 会记录手机当前物理上联网卡的接口、网关、源地址和路由表。当网络从 Wi-Fi 切换到移动数据、从移动数据返回 Wi-Fi，或默认网关/IP 改变时，模块会等待短暂防抖后立即重建 EasyTier，不再只监听 Clash 等外部 VPN 的出现与消失。

模块还会周期检查 EasyTier RPC。若 `easytier-cli route list` 连续超时或返回无效内容，即使 PID 和 TUN 仍存在，也会判定核心处于半失效状态并重启。没有远端节点时，只有 RPC 正常且仍存在真实传输 socket 才允许核心继续自行重连；RPC 超时或传输端点归零时不会再无限抑制恢复。

官方 EasyTier APP VPN 现在作为独立冲突处理：模块暂停自己的核心并保留原始故障原因，APP VPN 关闭后自动恢复。核心停止时不会再按相同虚拟 IP 把 APP 的 `tun0` 误认为 TierNest TUN。

## EasyTier 传输端点观测

`v0.5.0-beta.13` 会只读检查 EasyTier 进程实际持有的 IPv4 TCP/UDP socket inode，记录远端 IP、端口和 Android 当前的路由决策，并在外部 VPN/健康恢复重启前后各保存一份快照。记录位于：

```text
/data/adb/modules/tiernest/logs/transport.log
/data/adb/modules/tiernest/run/transport-endpoints.txt
```

该功能用于判断断联究竟发生在 EasyTier 虚拟路由还是公网传输层；当前只观察，不自动给公网端点添加旁路规则。默认最多记录 64 个端点，可在 `settings.conf` 设置 `TRANSPORT_OBSERVER_ENABLED` 和 `TRANSPORT_ENDPOINT_LIMIT`。

## 自动健康恢复

历史设备私密包会每 20 秒检查家庭路由器代理网段。检测异常时先重新协调表 `20110`；若互联网正常但 EasyTier/代理网段连续两次失败，则在启动宽限期与冷却时间满足后自动重启 EasyTier。该逻辑用于修复“OpenWrt 节点已重新出现，但 `192.168.50.0/24` 仍被外部 VPN 接管”的断联。通用包默认关闭健康目标，避免硬编码用户网络。

## 路由方案一键切换

`v0.5.0-beta.22` 在 WebUI 设置页提供两套持久化路由方案：

- **官方兼容方案**：使用 `auto/upstream`，关闭 Android 物理网络表镜像，适合小米/HyperOS；
- **TierNest 经典方案**：固定 dedicated 表 `20110`，并把 EasyTier CIDR 镜像到活动的 `rmnet_data*` / `wlan*` 表，适合 OnePlus Ace 3 Pro。

点击方案卡片后，模块会原子保存到 `config/route-strategy.state`，清理旧路由与规则并自动重启 EasyTier。用户选择会在重启和升级后保留。也可使用命令：

```sh
su -c '/data/adb/modules/tiernest/control.sh route-strategy-status'
su -c '/data/adb/modules/tiernest/control.sh route-strategy-official'
su -c '/data/adb/modules/tiernest/control.sh route-strategy-legacy'
```

## OnePlus Ace 3 Pro 专用路由基线

从 `v0.5.0-beta.22` 起，Ace 私密包使用 `ROUTE_STRATEGY_DEFAULT=legacy`，由策略层在运行时启用 dedicated 表和 Android 网络表镜像；基础设置仍为 `ROUTE_MODE=auto` 和 `ROUTE_AUTO_SWITCH_ENABLED=1`，以支持用户切换到官方兼容方案。不要把基础设置误判成经典方案未生效，也不要覆盖用户已保存的策略。移动数据下若 Internet 正常、RPC 正常，但所有公网 Peer 长期停留在 TCP `SYN_SENT` 且 route list 只有 Local，应首先核对最终 ZIP 内的设备路由配置。

## Android 热点设备单向访问 EasyTier

`v0.5.0-beta.22` 增加了默认关闭的“热点设备单向访问”模式。它只解决以下方向：

```text
热点电脑/平板  ->  EasyTier 虚拟节点或远端代理网段
```

它不会把热点网段加入 `proxy_networks`，也不会允许 EasyTier 节点主动连接热点客户端。实现采用目标网段限定的 SNAT 与策略路由：只有当前确实经 EasyTier TUN 路由的虚拟/代理 CIDR 会进入专用链；普通互联网、物理网卡路由和默认路由不会被接管。返回方向仅放行 `ESTABLISHED,RELATED`，其余从 EasyTier 转发到热点网段的新连接会被显式丢弃。

在 WebUI 的 **设置 -> 热点设备单向访问** 中手动启用。通用包和私密包都默认关闭，升级不会继承 beta.15 的旧热点开关。为了降低对 Android tethering/netd 的影响，新模式不修改全局 `ip_forward` 或接口 `rp_filter`，只在 Android 热点本身已经启用转发时工作；自动检测也只接受高可信热点接口，不再把普通 `wlan*` 当作热点。USB 共享或特殊 ROM 接口可在 `settings.conf` 显式指定。

如果 `config.toml` 中把热点网段配置到了 `proxy_networks`，单向模式会拒绝启动，因为那会向组网发布热点子网并破坏“对端不能主动访问”的保证。

## 已知限制

- 当前安装包只包含官方 Linux `aarch64` 静态二进制；
- 路由保护与热点单向访问当前只覆盖 IPv4；
- 另一个 VPN 仍可能承载 EasyTier 到公网 Peer 的底层连接；
- 默认不接管出口节点路由；如确实需要 EasyTier Exit Node，可在 `settings.conf` 中设置
  `ALLOW_EXIT_ROUTES=1`，但这可能与另一个 VPN 冲突；
- 尚未提供独立 Android 管理 App；当前管理入口为 KernelSU WebUI。

## 卸载与系统恢复

`v0.5.0-beta.22` 卸载时先标记模块移除并终止守护/监测进程，等待退出后再执行最终幂等清理：删除新模式的 `TN_HS_OUT_NAT` / `TN_HS_OUT_FWD` 规则、精确记录的热点目标策略规则、旧版 `TN_HS_NAT` / `TN_HS_FWD` 遗留物、TierNest 请求表与实际回退表的规则和路由，以及 PID/锁文件。新单向模式本身不修改 `ip_forward` 或 `rp_filter`；仅升级清理旧 beta.15 遗留时才恢复旧版保存过的 sysctl。

安装器只会恢复由 TierNest 自己临时禁用的旧 `easytier_magisk` 模块；用户原本就禁用的旧模块不会被误启用。导出到 Download 的诊断文件属于用户文件，不会在卸载时自动删除。

## 上游与许可

EasyTier 核心来自 EasyTier 项目。TierNest 的脚本包含基于上游模块思路重新实现的部分，
整体使用 Apache License 2.0。详见 `LICENSE` 和 `THIRD_PARTY_NOTICES.md`。

## 历史：v0.5.0-beta.23 拓扑地理位置修复（beta.24 已改为路由树）

- 显式经纬度优先；没有经纬度时，离线解析位置标注/节点名中的城市名称（中文、英文及常用独立缩写），适用于设备和公网节点。
- 已识别的公网节点按地图投影显示，不再被强制放进中继栏。同城节点的显示偏移用引线连接真实坐标圆点。
- 未定位节点和当前视图之外的节点统一放到底部非地理位置栏；海外节点可切换世界地图查看。
- 名称推断仅为城市级提示，不是 GPS 或实时公网 IP 定位。没有城市线索的移动设备需在“编辑位置”中填写，不能根据虚拟 IP 或下一跳的位置推断设备所在地。
- 本版不调整三台设备的路由策略、网络身份或配置迁移版本。
