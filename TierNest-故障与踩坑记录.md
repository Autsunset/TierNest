# TierNest 故障与踩坑记录

> 隐私说明：本文节点名、网络地址、端点、MAC 和位置均已替换为示例值，不用于连接真实设备。历史记录用于解释故障机制，当前升级策略以 AGENTS.md 为准。

> 仓库脱敏维护：Android 网络表诊断直接显示已记录的表，不再按开发者的固定子网过滤；私人配置、截图、原始日志与历史构建保存在仓库外。

> 文档类型：维护参考（Reference）与故障解释（Explanation）  
> 适用对象：TierNest 开发者、设备包维护者、真机测试人员  
> 最后更新：2026-09-01  
> 当前对应版本：`v1.0.1` / EasyTier `v2.6.4`

本文记录 TierNest 在 Android 13/16、KernelSU、厂商 ROM、外部 VPN、Wi-Fi/移动数据切换和热点共享场景中已经遇到的真实问题。目标不是记录每一行改动，而是避免后续版本重复踩坑。

---


## 2026-09-19：App alpha02 设置与切页

- 配置页按模块的基本信息、节点/监听、网络参数和 TOML 分组，逐条编辑地址，增加监听
  预设和固定保存栏。非受支持的路由/热点能力仍明确保留限制，未增加失效开关。
- 参考 interstellar-proxy 的 MIT 许可界面，新增可切换的星际外观与分类设置行；旧主题
  偏好保留，静态光晕避免持续动画。来源和许可证随 APK 保留。
- 原切页通过条件分支销毁/重建页面，偏好同步 commit 写盘会占用主线程；现改为原生
  Pager、保留邻页与 ViewModel 草稿，写盘移到 IO 线程，节点解析和路由计算移到后台。
  设置页停止连续状态采样；已开始的有界 RPC 先完整接收，避免切页取消留下半包。
- alpha01 是调试构建；alpha02 默认构建 R8 优化的 Release APK，沿用测试签名以便覆盖
  安装。不得用 debug 包的帧时间评价优化后的 Compose 界面。
- 设置子页 180 ms 位移/透明度过渡，减少动态效果时仅 120 ms 淡入淡出。没有不断重复
  的装饰动画，系统关闭动画同样生效。
- 新草稿回归覆盖原文/注释不变、特性与未知字段保留、损坏 TOML 不丢输入，以及保存
  响应不能覆盖后续编辑。覆盖安装检查现有配置/偏好字节，不重置用户配置。

## 2026-09-19：独立 App 开发与验证边界

- 新增独立 Root App；更换包装形式不能自动消除 EasyTier 心跳与打洞耗电。锁屏暂停
  采用显式停止/重新建连，默认关闭，不承诺无损恢复。
- 不复制 MoonTier 无明确许可证的源码与库。EasyTier v2.6.4 许可证核对为 LGPL-3.0，
  修正项目原有 Apache-2.0 标注。
- Root App 管道生命周期、动态路由表避让、精确删除与失败回滚单独实现；不复用
  `ip rule del pref ...` 或 flush 整表的宽泛清理方式。现有模块快照变量隔离修复未改动。
- 新 App 保存前备份到 Download，导入模块时复制并校验整个配置树和设置；原件
  保留。命令参数、旧路由策略及热点行为不能直接等价时阻止连接并要求明确选择。
- Android 8 兼容检查发现 `NetworkRequest.clearCapabilities`、`InputStream.readNBytes`
  的 API 级别限制，改成旧版本可用的实现；快捷磁贴按 API 级别选择 PendingIntent。
- 本地模拟器发现强制深色与系统状态栏图标颜色不一致、切页丢失配置草稿，已修复。
- Android 16 x86_64 redroid 虽宣称支持 arm64 APK 翻译，不能据此推断原生 ARM Linux
  可执行文件可运行；其普通 App 无 su 执行权限，且内核缺少 iptables filter 表。
  这些条件限制完整 Root App 验收，不能把 ADB Root 测试记作 App 获权测试。
- 本地 RPC 无认证，仅绑定 localhost 不足以保护配置；新 App 增加仅 Root 可调用
  的回环防火墙规则，缺少必要内核功能时拒绝启动，不放宽系统全局防火墙。
- redroid 真机命令验证发现 toybox `mktemp` 不接受 `XXXXXX.toml` 后缀模板；GNU/Linux
  离线测试没有暴露此差异。改用 noclobber 原子预留最终 `.toml` 文件名，保留禁止覆盖
  与逐字节校验，再在 Android 上复验同秒连续备份。

详细实施与真机验收清单见 `android/PLAN.zh-CN.md`。开发 APK 和离线回归不代替
普通应用 TCP、Clash 共存、拔线待机与升级/重启验证。

## 1. 故障分析必须区分“初始根因”和“后续应急操作”

### 现象

用户发现 TierNest 不通后打开官方 EasyTier APP。最终诊断显示：

```text
VPN:com.kkrainbow.easytier
sessionId=TauriVpnService
tun0 = 10.42.0.10/24
TierNest core = stopped
```

如果只看诊断末态，很容易得出错误结论：官方 APP 导致了全部故障。

### 实际因果链

2026-09-01 的 OnePlus Ace 3 Pro 故障实际为：

```text
Wi-Fi 底层 DNS/TCP 异常
→ EasyTier 传输连接失效
→ 手机切换到移动数据
→ 模块未立即重建或路由模式不兼容
→ 用户发现 TierNest 无效
→ 用户打开官方 APP 应急
→ APP 与模块同 IP 冲突
→ TierNest 最终停止
```

### 维护要求

诊断时必须按时间顺序回答：

1. 用户第一次发现不可用之前发生了什么？
2. 官方 APP、Clash、手动重启是原因还是应急行为？
3. `last_recovery_event` 是否覆盖了更早的真实故障？
4. 诊断末态是否只是用户排障后的状态？

不能仅凭最后一个 `core_pid=stopped` 或 `external_vpn=tun0` 判断根因。

---

## 2. PID、TUN、RPC 和数据面是四个不同的健康层级

### 错误假设

```text
有 easytier-core PID
+ 有 tiernest0
= EasyTier 正常
```

这个假设不成立。

### 已观察到的半失效状态

```text
PID 存活
TUN 存在
RPC route list 超时
传输端点为 0
虚拟 IP 不通
```

还可能出现：

```text
RPC 正常
route list 只有 Local
公网 socket 全部 SYN_SENT
数据面仍不可用
```

### 正确检查顺序

1. `core_pid` 是否属于模块管理的二进制；
2. TUN 是否由当前 PID 创建；
3. `easytier-cli route list` 是否在超时内返回有效 JSON；
4. 是否存在远端路由；
5. 传输 socket 是否真正建立；
6. 强制 TUN 探测是否成功；
7. 普通应用路由是否成功。

### 代码要求

- `find_tun_device` 必须先确认 `core_running`；
- 核心停止后不能按虚拟 IP兜底认领其他程序的 `tunX`；
- `sync_route_guard` 在核心停止时必须失败关闭并清理模块路由；
- RPC 连续超时必须判定为半失效核心，而不是继续依赖 PID。

---

## 3. `/proc/net/tcp` 状态不能全部算作“活跃传输”

EasyTier 传输观察器读取 `/proc/<pid>/net/tcp*`。关键状态：

| 十六进制状态 | 含义 | 是否可视为健康传输 |
| --- | --- | --- |
| `01` | `ESTABLISHED` | 是 |
| `02` | `SYN_SENT` | 否，只是连接尝试 |
| `08` | `CLOSE_WAIT` | 否，连接已失效/等待关闭 |
| UDP `07` | 常见 UDP 远端端点状态 | 可按已连接 UDP 统计 |

### 已发生的错误

beta.18 的 `live_transport_endpoint_count` 最初直接统计所有远端 socket，导致多个 `SYN_SENT` 被视为“仍有活跃端点”，进而触发：

```text
Health restart suppressed: EasyTier has no remote peers; allowing the core to continue reconnecting
```

但当时并没有任何已建立连接。

### 正确规则

只有以下状态可以抑制健康重启：

```text
TCP state = 01
UDP remote state = 07
```

`SYN_SENT`、`CLOSE_WAIT` 和不断更换 inode 的连接尝试都不能证明数据面健康。

---

## 4. 物理上联变化和外部 VPN 变化不能混为一谈

### 外部 VPN 变化

例如：

```text
none -> tun0=172.20.0.1/30
```

通常代表 Clash、sing-box、WireGuard 或其他 VPN 接口出现。

### 物理上联变化

例如：

```text
dev=wlan0|via=192.0.2.1|src=192.0.2.105|table=wlan0
→
dev=rmnet_data3|via=100.x.x.x|src=100.x.x.x|table=rmnet_data3
```

这代表 Wi-Fi 与移动数据切换。

### 已发生的问题

beta.16 只监听外部 VPN 接口变化，没有在 Wi-Fi → 移动数据时立即重建 EasyTier。结果是普通互联网已恢复，但 EasyTier 仍保留旧连接状态。

### 正确实现

物理上联签名至少应包含：

```text
接口 dev
网关 via
源地址 src
实际路由表 table
```

变化后：

1. 等待 3–5 秒防抖；
2. 再次确认签名稳定；
3. 清理 TUN/路由；
4. 重启核心；
5. 重新同步路由和热点规则；
6. 设置冷却时间，避免网络抖动导致重启风暴。

---

## 5. OnePlus Ace 3 Pro 不能随意回退到 upstream/auto

### 已验证基线

Ace 3 Pro 在 beta.8/beta.12 已验证的稳定路由模式是：

```sh
ROUTE_MODE=dedicated
ROUTE_AUTO_SWITCH_ENABLED=0
ROUTE_TABLE=20110
ROUTE_RULE_PRIORITY=9980
```

### beta.18 回归

设备包构建脚本先统一写入：

```sh
ROUTE_MODE=auto
```

Ace 分支又错误地设置：

```sh
PROFILE_ROUTE_MODE=auto
```

导致真机实际运行：

```text
route_mode_config=auto
route_mode_active=upstream
rule_priority=9999
```

移动数据下表现为：

```text
Internet Ping 正常
RPC 正常
route list 只有 Local
所有公网 TCP socket 长期 SYN_SENT
所有 Peer connect timeout
```

健康重启只能反复重现同一个错误路由环境，无法修复。

### 维护要求

设备包不能只在 `device-profile.txt` 写说明，必须真正修改打包后的 `settings.conf`：

```sh
ROUTE_MODE=dedicated
ROUTE_AUTO_SWITCH_ENABLED=0
```

Ace profile revision 应在基线发生变化时递增，并在构建后解包核对。

### 发布检查

```sh
unzip -p <Ace包.zip> settings.conf | grep -E 'ROUTE_MODE|ROUTE_AUTO_SWITCH'
unzip -p <Ace包.zip> config/device-profile.txt | grep -E 'profile_revision|route_mode'
```

期望：

```text
ROUTE_MODE=dedicated
ROUTE_AUTO_SWITCH_ENABLED=0
route_mode=dedicated
```

---

## 6. 设备 profile 元数据不能与真正打包配置分离

### 风险

以下状态是无效的：

```text
device-profile.txt: route_mode=dedicated
settings.conf: ROUTE_MODE=auto
```

元数据看起来正确，但运行时根本不读取它。

### 要求

每个 profile 相关字段都必须明确属于哪一类：

- 运行时真正读取的配置；
- 安装迁移判断；
- 仅供人阅读的说明。

发布测试必须检查最终 ZIP，不应只检查构建脚本源码或临时目录。

---

## 7. 官方 EasyTier APP VPN 是冲突，但不一定是初始根因

官方 APP 常见信号：

```text
VPN:com.kkrainbow.easytier
sessionId=TauriVpnService
OwnerUid=<APP UID>
```

如果 APP 和模块使用相同虚拟 IP：

```text
TierNest tiernest0 = 10.42.0.10/24
APP tun0          = 10.42.0.10/24
```

则必须视为冲突。

### 正确处理

- 不把 APP VPN 当作普通外部 VPN；
- 单独记录 `last_easytier_app_conflict`；
- 暂停模块核心；
- 不覆盖之前的 underlay/RPC 故障原因；
- APP VPN 关闭后自动恢复模块；
- 核心停止时不能把 APP 的 `tun0` 认作模块 TUN。

---

## 8. health restart suppression 必须非常保守

### 旧逻辑

```text
route list 只有 Local
→ 假定 EasyTier 正在重连
→ 抑制重启
```

这在以下状态会出错：

```text
RPC 超时
无已建立 socket
只有 SYN_SENT
底层网络已经恢复
核心长期没有任何 Peer
```

### 正确抑制条件

只有全部成立才可等待：

```text
health_state = overlay-unreachable
RPC = healthy
remote_peer_count = 0
至少存在一个已建立传输端点
```

其他情况应进入冷却保护的重启流程。

---

## 9. Ping 成功与否不能单独代表互联网或 EasyTier 健康

### 常见误判

- 运营商可能屏蔽 `1.1.1.1` ICMP；
- 目标设备可能屏蔽 Ping，但 HTTP/SSH 正常；
- 代理网段某个 TCP 端口关闭不代表整网断开；
- `proxy=OK` 可能是另一条 VPN 或本地重叠路由提供的结果。

### 建议组合

- 默认路由是否存在；
- 公网 IP TCP 是否可以连接；
- DNS 是否可以解析；
- EasyTier RPC 是否正常；
- 是否存在已建立传输端点；
- 强制 TUN Ping；
- 代理网段 TCP 探测。

探测结果必须注明路径，不能只输出 `OK/FAIL`。

---

## 10. KCP 与 smoltcp 不是所有 TCP 故障的答案

### 小米/HyperOS 已验证问题

```text
enable_kcp_proxy=true
use_smoltcp=false
```

可能导致：

```text
Ping 正常
HTTP/SSH 超时
```

### 稳定默认值

```toml
[flags]
enable_kcp_proxy = false
use_smoltcp = false
```

### 判断边界

如果表现是：

```text
公网 Peer 连接全部 SYN_SENT
DNS resolve timeout
route list 只有 Local
```

优先检查物理上联和 Android 路由模式，不应先切换 KCP。

---

## 11. Android 13 与 Android 16 的路由表能力不同

部分 Android 13 `ip` 不接受：

```sh
ip route show table 20110
```

模块必须探测能力并选择低位回退表，例如 `110`。

### 维护要求

- 状态同时显示 requested/effective table；
- 所有添加、验证、清理都使用 effective table；
- 卸载时同时清理请求表和实际表；
- 不要在新功能中重新硬编码 `20110`。

---

## 12. 家庭局域网与远端 proxy CIDR 重叠

示例：OpenWrt 发布：

```text
192.168.50.0/24
```

手机回家后本地 Wi-Fi 也是同一网段。

### 要求

- 在家优先 `wlan0` 直连；
- 离家恢复 `tiernest0`；
- 本地物理路由不能进入远端 TUN NAT；
- dedicated 表必须镜像本地直连覆盖；
- 回家/离家时自动切换，不要求用户改配置。

---

## 13. 热点单向访问不能使用 `proxy_networks`

用户需求如果是：

```text
热点客户端 -> EasyTier 节点
但 EasyTier 节点不能主动访问热点客户端
```

则不能发布：

```toml
proxy_networks = ["热点网段"]
```

因为这会向整个组网声明热点子网可达。

### 正确模式

- 热点客户端到 EasyTier 目标做 SNAT；
- 只允许当前确实经 TUN 路由的 CIDR；
- 返回方向只允许 `ESTABLISHED,RELATED`；
- 其余 EasyTier → 热点流量显式 `DROP`；
- 不接管热点普通互联网；
- 不修改全局 `ip_forward`/`rp_filter`；
- 检测到热点 CIDR 出现在 `proxy_networks` 时拒绝启动。

---

## 14. 热点接口自动检测必须宁可漏报，不能误报

旧实现接受普通 `wlan*`，可能把手机当前 Wi-Fi 上联误认为热点。

### 自动检测白名单

优先：

```text
ap0
ap_*
apbr*
swlan*
softap*
br_tether*
```

USB/RNDIS 默认关闭，需要显式开启。

普通 `wlan0` 不应自动识别为热点；特殊 ROM 应允许在 `settings.conf` 手工指定。

---

## 15. iptables 规则必须有所有权、作用域和失败回滚

### 不安全做法

- 在父链插入无条件跳转；
- 仅按 priority 删除 `ip rule`；
- 清空非本模块链；
- 规则应用一半就留下状态；
- 清理循环无上限；
- 守护进程和 WebUI 同时改规则。

### 当前要求

- 使用独立链；
- 父链 hook 限定接口、方向和源网段；
- 先准备子链和策略规则，最后发布 hook；
- 记录 `priority|interface|CIDR|table`；
- 删除前核对整条规则；
- 失败时回滚部分状态；
- 使用锁串行化；
- 清理循环设置上限；
- 普通互联网不得经过目标链或被 NAT。

---

## 16. Shell 函数变量默认可能污染调用者

Android `/system/bin/sh` 和 BusyBox `ash` 中，函数变量不是自动局部变量。

### 已发生的问题

内层函数使用：

```sh
iface=
reason=
status=
```

覆盖外层状态，导致：

- 热点 CIDR/接口被改写；
- 恢复原因嵌套；
- 状态检查使用空接口；
- 日志出现错误 reason。

### 规则

- 只读/判断函数尽量使用子 shell：

```sh
helper() (
    ...
)
```

- 必须修改外部状态的函数使用带前缀变量名；
- 不使用过于通用的 `pid`、`state`、`reason`、`iface`；
- 新增嵌套调用后必须检查变量污染。

---

## 17. 清理函数不能假设底层命令永远诚实

某些 ROM 或 mock 环境可能出现：

```text
iptables -C 返回成功
iptables -D 也返回成功
但规则实际未消失
```

无上限的：

```sh
while iptables -C ...; do iptables -D ...; done
```

可能永久卡住卸载或守护进程。

### 要求

所有重复清理必须有限次，例如 8/16 次，并在超限后记录警告。

---

## 18. 网络快照变化不等于物理网络变化

`network_watch.sh` 的完整签名包含路由、接口和连接状态。EasyTier 自己不断创建/关闭 socket 也会让快照频繁变化。

不能把每个 `network-state-changed` 都理解为 Wi-Fi/移动网络切换。

物理网络恢复逻辑必须使用独立、稳定的 underlay signature，而不是直接复用完整网络快照校验值。

---

## 19. 时间戳需要统一时区

EasyTier Rust 日志常使用 UTC：

```text
2026-09-01T03:07:35Z
```

TierNest Shell 日志使用手机本地时区：

```text
2026-09-01 11:07:35
```

在中国时区两者相差 8 小时。分析时间线时必须先转换，否则会误认为日志来自不同启动周期。

---

## 20. 诊断报告必须保留故障前证据

只导出当前状态不够。应保留：

- 最近物理上联变化；
- 最近外部 VPN 变化；
- 官方 APP 冲突状态；
- 最近恢复原因和结果；
- RPC 状态；
- 传输 socket 状态；
- route list；
- 重启前后端点快照；
- 核心重要错误；
- 完整模块日志和网络监测日志。

应急操作不能覆盖初始故障记录。

---

## 21. 私密包升级与 profile migration

### 必须保留

- 用户的 `config.toml`，除非 profile revision 明确要求迁移；
- 配置备份；
- 节点位置；
- 新版热点单向访问偏好。

### 不应继承

- beta.15 旧热点 NAT 开关；
- 已废弃的运行状态文件；
- 旧 iptables/rp_filter/ip_forward 状态；
- 与当前设备不匹配的 hostname/IPv4 profile。

### profile revision 何时递增

- TUN 名称基线改变；
- KCP/smoltcp 安全默认改变；
- 设备固定路由模式改变；
- 旧配置会直接导致该设备无法联网。

---

## 22. 发布前真机/自动化检查清单

### 通用检查

- [ ] 所有 Shell 通过 `/system/bin/sh`/BusyBox `ash -n`；
- [ ] WebUI 构建后无外部运行依赖；
- [ ] 核心停止时 `find_tun_device` 返回空；
- [ ] 核心停止时 route guard 清理并退出；
- [ ] 外部 VPN 开/关能够恢复；
- [ ] Wi-Fi ↔ 移动数据切换能够恢复；
- [ ] RPC 超时能够恢复；
- [ ] 只有 SYN_SENT 时不会抑制健康恢复；
- [ ] 官方 APP VPN 能独立识别并在关闭后恢复；
- [ ] 卸载不留下规则、链、锁和运行文件；
- [ ] 诊断不泄露 `network_secret`。

### Ace 3 Pro 专项

- [ ] ZIP 内 `ROUTE_MODE=dedicated`；
- [ ] ZIP 内 `ROUTE_AUTO_SWITCH_ENABLED=0`；
- [ ] profile `route_mode=dedicated`；
- [ ] 移动数据下至少一个公网 Peer TCP 成为 `ESTABLISHED (01)`；
- [ ] route list 出现远端节点；
- [ ] `10.42.0.1` 和 `192.168.50.1` 可达；
- [ ] Wi-Fi 与移动数据来回切换后仍能恢复。

### 热点单向访问专项

- [ ] 默认关闭；
- [ ] 只匹配 EasyTier 目标 CIDR；
- [ ] 普通互联网仍由 Android/客户端 Clash 处理；
- [ ] 热点客户端可以主动访问组网；
- [ ] 组网节点不能主动访问热点客户端；
- [ ] 关闭热点后规则自动清理；
- [ ] `proxy_networks` 与热点 CIDR 重叠时拒绝启动。

---

## 23. 常用诊断判读速查

### 核心正常且已连接

```text
rpc_state=healthy
remote_peer_count>0
TCP state=01
route list 有远端节点
```

### 核心假在线

```text
PID 存在
TUN 存在
rpc_state=timeout/invalid
```

### 底层路由/运营商连接问题

```text
internet=OK 或有默认路由
所有公网 Peer 长期 state=02
直接 IP connect timeout
域名 resolve timeout
route list 只有 Local
```

### 路由模式回归

```text
设备应为 dedicated
实际 route_mode_active=upstream
移动数据全部 SYN_SENT
```

### 官方 APP 冲突

```text
easytier_app_vpn=active
VPN:com.kkrainbow.easytier
sessionId=TauriVpnService
```

### 仅代理网段不通

```text
虚拟 Peer 可达
proxy 目标失败
forced TUN 正常
```

优先检查代理路由同步、远端网关、防火墙和本地网段重叠。

---

## 24. 本文维护规则

每次真机问题确认后，应新增：

1. 用户看到的现象；
2. 最初根因；
3. 容易产生的错误判断；
4. 关键诊断证据；
5. 代码修复原则；
6. 防回归测试；
7. 是否需要设备 profile revision。

不要只在 `CHANGELOG.md` 写“修复某问题”。Changelog 面向版本变化，本文面向长期工程约束。
---

## 25. 已连接、代理 Ping 可用，但 TCP/HTTP 不通：检查 Android TUN INPUT/OUTPUT

### 2026-09-01 Ace 3 Pro 复现

```text
route_mode=dedicated
RPC=healthy
remote_peer_count=9
TCP ESTABLISHED transport=8
192.168.50.1 Ping=OK
192.168.50.1:80=FAIL
```

开发机从家庭局域网直接验证 `192.168.50.1:22` 和 `:80` 均开放，因此不是远端服务关闭。

### 判定

Root 创建的 TUN 与 Android `VpnService` 不同。厂商防火墙可能允许 TUN 上的 ICMP，却阻止进入本机 TCP 栈的 INPUT/OUTPUT 流量。官方 APP 可用不能证明 Root TUN 的 netfilter 路径可用。

### 最小修复

设备专用包启用：

```sh
TUN_FIREWALL_GUARD=1
```

规则必须满足：

- 使用独立 `TN_ET_INPUT` / `TN_ET_OUTPUT` 链；
- INPUT 同时匹配 `-i tiernest0` 和远端 EasyTier 源 CIDR；
- OUTPUT 同时匹配 `-o tiernest0` 和远端 EasyTier 目标 CIDR；
- 不加入默认路由；
- 不对其他接口或普通互联网执行 ACCEPT；
- 停止、重启、卸载时完整清理；
- 诊断导出链规则与包/字节计数，以确认 TCP 包是否命中。

### 排障顺序

1. 确认公网 transport 至少一个 TCP `01`；
2. route list 中有真实虚拟节点和 proxy CIDR；
3. `ip route get` 指向 EasyTier TUN；
4. Proxy Ping 成功但已知开放 TCP 端口失败；
5. 查看 `TN_ET_INPUT` / `TN_ET_OUTPUT` 计数；
6. 若 OUTPUT 增长而 INPUT 不增长，检查远端返回或中间链路；
7. 若 INPUT 有包但 TCP 仍失败，再检查 MTU、校验和与远端 proxy 实现。


---

## 26. 单次成功快照不能证明某个版本长期稳定

2026-08-31 的 beta.13 Ace 诊断中，同一个 PID、相同 dedicated 路由、相同 EasyTier 核心和配置出现了：

```text
04:29:44  virtual Ping=OK, proxy Ping=OK, TCP 80=OK
04:29:57  virtual Ping=FAIL, proxy Ping=FAIL, TCP 80=FAIL
```

两次只相差 13 秒，公网传输 socket 仍有多个 `ESTABLISHED`。因此不能把 04:29:44 的单次成功当作“beta.13 已长期验证正常”。

### beta.20 防火墙反证

beta.20 的 TUN 防火墙计数显示：

```text
TN_ET_OUTPUT / 192.168.50.0/24: 113 packets, 10206 bytes
TN_ET_INPUT  / 192.168.50.0/24:  65 packets, 22577 bytes
```

说明请求和返回流量都已经穿过 Android INPUT/OUTPUT hook。即使 TCP 探测仍失败，也不能继续把根因归咎于“防火墙完全阻断 TUN”。该 guard 可用于计数和兼容，但不是本次故障的充分修复。

### 必须执行同环境 A/B

当新旧版本核心二进制、`config.toml` 和 dedicated 路由基线相同，但用户认为旧版可用时，必须：

1. 在同一手机、同一移动网络、同一远端节点条件下安装精确旧包；
2. 重启，确保旧内核规则消失；
3. 不打开官方 APP，不打开热点；
4. 分别在启动后 1 分钟和 5 分钟采集诊断；
5. 对比 route list、Peer ID、路径、transport socket、探测和系统规则。

旧包也失败则说明问题不由新脚本引入；旧包稳定成功才继续做逐文件二分。
---

## 27. Ace 的 beta.8 自有方案 = dedicated + Android 网络表镜像

只恢复 `ROUTE_MODE=dedicated` 并不等于恢复 beta.8 的完整实现。beta.8 设备包还包含：

```sh
SYNC_ANDROID_NETWORK_TABLES=1
```

beta.9 合并官方模块方式时同时发生了两项变化：

```text
新增 auto/upstream/target-main 模式
默认关闭 Android physical network table mirroring
```

小米设备适合官方方式，但 Ace 的应用 socket 可能带 Android fwmark 或绑定 `rmnet_data*` / `wlan*`。即使 Root `ip route get` 和 Ping 经过表 20110，浏览器/应用仍可能进入 Android 的物理网络表。如果这些表没有 EasyTier CIDR，就会表现为“组网已连接、Root 探测部分成功、应用无法访问”。

### Ace 完整旧基线

```sh
ROUTE_MODE=dedicated
ROUTE_AUTO_SWITCH_ENABLED=0
ROUTE_TABLE=20110
ROUTE_RULE_PRIORITY=9980
SYNC_ANDROID_NETWORK_TABLES=1
```

### 小米基线

```sh
ROUTE_MODE=auto
SYNC_ANDROID_NETWORK_TABLES=0
```

### 诊断确认

Ace 正常同步后，状态不应再是：

```text
Android app route mirrors = none
```

而应在 `android-route-specs.txt` 中看到类似：

```text
rmnet_data3|10.42.0.0/24|tiernest0
rmnet_data3|192.168.50.0/24|tiernest0
```

并在对应 Android 表中看到：

```text
10.42.0.0/24 dev tiernest0
192.168.50.0/24 dev tiernest0
```

设备 profile 构建测试必须同时核对 dedicated 与 mirroring，不能只检查 route mode。
---

## 28. 官方与经典路由方案必须可持久化手动切换

不同 ROM 的最优策略相反，不能继续依靠全局默认值或自动猜测：

```text
小米：官方兼容 auto/upstream，Android 表镜像关闭
Ace：TierNest 经典 dedicated，Android 表镜像开启
```

实现要求：

- 策略文件使用 `config/route-strategy.state`；
- 只允许 `official` / `legacy`；
- 切换时原子写入；
- 删除 route-mode runtime override；
- 清理旧表、旧规则、热点/TUN附加规则；
- 重启 EasyTier 后应用新策略；
- WebUI 当前方案按钮不可重复点击，另一方案一键切换；
- 升级必须保留用户选择；
- 设备包只定义默认值，不能覆盖已有 state。

策略语义必须固定：

```text
official -> ROUTE_MODE=auto/upstream, Android table mirroring off
legacy   -> dedicated table 20110, Android table mirroring on
```

不要把“当前 active mode 恰好是 dedicated”误认为用户选择了经典方案；official/auto 也可能自动降级到 dedicated，但它仍不启用 Android 表镜像。
---

## 29. 网关 KCP 是可验证假设，不能因症状相似直接认定

2026-09-01 beta.22 诊断表现为：

```text
手机 KCP=false
路由与 Android 表镜像正常
Proxy Ping=OK
TCP 80=FAIL
```

OpenWrt 真机当时运行：

```text
kcp_proxy=1
enable_kcp_proxy=true
use_smoltcp=false
```

这个组合与历史“Ping 正常、TCP 超时”症状相似，因此曾做过一次带备份的 KCP-off A/B。但用户指出同一 OpenWrt 下两台小米设备正常，并认为网关与 Ace 单机问题无关；配置随后完整回滚。

### 结论

- 远端网关参数必须同时检查 UCI、TOML 和真实进程命令行；
- 症状相似只能形成假设，不能直接修改共享网关并宣布根因；
- 同一网关下其他设备正常是重要反证；
- 修改共享基础设施前必须备份并能够立即回滚；
- 本次 OpenWrt KCP 修改已回滚，当前运行重新包含 `--enable-kcp-proxy`。

备份标记：

```text
bak-before-kcp-off-20260901-125328
```

---

## 30. 重复 Peer 条目不是充分故障条件

用户在模块失效后打开官方 EasyTier APP，OpenWrt `peer-center` 出现两个：

```text
Example-Phone-A / 10.42.0.10
```

它们具有不同 node ID 和传输协议。重复实例会污染诊断，测试模块前仍应强停官方 APP；但在 beta.22 恢复正常后，OpenWrt 实时列表仍暂时存在两个条目，同时：

```text
OpenWrt -> 10.42.0.10 Ping 3/3 成功
延迟约 51–59 ms
手机访问恢复
```

因此：

- 重复 Peer 是需要清理的干扰项；
- 但仅凭重复条目不能宣布它就是根因；
- 必须结合当前选路、包计数、丢包率和实际双向访问；
- 官方 APP应急操作仍要与最初故障分开分析；
- 组网可能在 APP 强停、模块重启或路径重新收敛后自行恢复。


---

## 31. 用卸载/重启时间线区分缓存、当前模块与另一台重复设备

2026-09-01 对 Ace 节点进行每 10 秒一次的 OpenWrt 实时监测，随后执行：

```text
卸载 TierNest
重启手机
重新安装 TierNest
再次重启
```

时间线：

```text
13:20:41  2391384056 + 3681865567
13:20:52  2391384056 消失，3681865567 继续收发
13:20:52–13:23:43  只有 3681865567，RX/TX 持续增长
13:23:54  新节点 3758756714 出现
13:24:48  3758756714 与 3681865567 同时持续收发
```

结论：

- `2391384056` 是卸载前当前手机模块实例；
- `3758756714` 是重装后的当前手机模块实例；
- `3681865567` 在当前手机模块不存在期间仍持续双向收发，确定属于另一台在线设备或独立运行环境；
- 它不是 Peer Center 缓存，也不是当前手机重启后恢复的同一个模块进程；
- 另一实例错误复用了 `Example-Phone-A / 10.42.0.10/24`。

同一虚拟 IP存在两个活跃 Peer 会导致路由和回程随机命中不同节点，表现为间歇性正常、TCP不稳定、Ping 与应用结果不一致。修复必须二选一：找到并停止 `3681865567` 的实际设备，或给当前 Ace 分配新的唯一虚拟 IP/hostname。


## 2026-09-06：beta.23 拓扑识别正确但落点错误

### 根因与修复

1. `layoutTopologyNodes` 已按推断经纬度投影，最后却按 `kind=public` 将所有公网节点 y 坐标钳制到 318–338，覆盖有效地理位置。现在只有未定位/视图外节点进底栏，不按公网身份覆盖坐标。
2. 碰撞处理直接把坐标移动 34/46 像素，没有标记原始位置。同城节点现在保留投影锚点，小幅避让并用引线和圆点展示真实位置。
3. 普通设备和中文位置标注未参与名称推断；同时旧短缩写正则可误匹配名称内部字符。现在各类节点统一解析城市线索，英文提示有字母边界，多个城市冲突则不猜测。
4. 缺失 `path_len` 被当成 0，可能误判本机；自定义 local 角色和按延迟排序生成的 ID 也会导致图示/选中对象错误。现在显式 Local 优先，缺失跳数不制造本机，节点 ID 基于身份。
5. 空位置配置刷新后仍保留旧缓存；现在空配置会清空缓存。

### 验证与约束

- `tests/test-topology-geography.mjs` 覆盖实际投影数值、手工坐标优先、空/非法坐标、零经纬度、城市推断、误匹配、视图外节点、同城锚点、筛选、角色和稳定 ID。
- 浏览器用同处深圳的手动网关与自动识别公网节点检查两者锚点一致，不能只测试 SVG 内是否存在“推断”文本。
- 自动识别仍是离线名称推断，不是 GPS/IP 查询。未获得地理依据的节点必须显示未定位，不得拿公网中继位置冒充远端设备位置。
- 沿用 beta.22 的 Ace legacy / 小米 official 默认策略及 profile revision，避免以 UI 更新为由覆盖用户配置或路由选择。

### 本轮发布记录

2026-09-06：完整 `scripts/validate-module.sh`、Chrome 浏览器集成测试和新增地理回归通过，`npm audit` 未报告已知漏洞。三个自用包的网络配置与输入文件逐字节相同，设备 profile revision 未变；包内 WebUI 和核心与本地已验证产物一致。通过既有 SSH 通道上传至飞牛 `<NAS 备份目录>/<版本目录>`，远端三个 ZIP 的 SHA-256 全部匹配。未远程安装或重启 Android 设备，本轮不包含三台真机刷机后的连通性验证。本地验证记录保存在 `.private/validation-beta23/`。


## 2026-09-06：beta.24 放弃地理地图，改为本机路由拓扑树

用户明确不再需要地图；删除地图底图、经纬度/城市识别和位置编辑界面，改为真实路由关系驱动的纵向连接树。历史位置配置不删除，后端接口保留供回退，但前端不再读取或据此判断节点角色。

### 不能再踩的路径推断问题

- `next_hop` 是本机到目标的第一跳，不等于目标的直接父节点。两跳且下一跳确认为直连时，才可用实线连接下一跳和目标；更长路径必须明确未展开并画虚线。
- 跳数缺失/矛盾、下一跳同名歧义和环路，不得回落为 DIRECT；缺失下一跳显示非在线计数的占位。
- 同名节点用下一跳 IP 进一步辨别；不存在唯一匹配时显示待确认。
- 代理网段全部附着在发布者，不得先生成大量边后只截取部分节点，造成悬空边。
- 筛选仅虚拟节点时，折叠路径仍保留公网节点名称，不把中继显示为直连。

### 展示与回归

纯数据逻辑独立到 `webui/src/topology.js`，`tests/test-topology-graph.mjs` 覆盖直连、二跳/多跳、缺失信息、同名、环路、筛选、完整代理网段、输入乱序、无本机和布局不重叠。浏览器测试验证实际 SVG 连线端点、键盘选择、路径高亮、刷新滚动状态、无地图元素、空拓扑清理和 360/412/768px 宽度不溢出。地图相关 d3-geo/topojson-client/world-atlas 依赖已移除。

### beta.24 发布核验

2026-09-06：最终 `scripts/validate-module.sh` 全部通过，依赖审计 0 已知漏洞。三个自用 ZIP 已核验原配置字节、profile revision、路由策略、版本、核心和 WebUI，并通过 SSH 上传至飞牛 `<NAS 备份目录>/<版本目录>`。远端三个 ZIP、安装说明和模拟数据预览图 SHA-256 全部匹配。测试和上传记录位于 `.private/validation-beta24/`；没有远程刷入或重启 Android 设备，不宣称完成升级后真机联网测试。


## 2026-09-06：v1.0.0 修复 beta.24 审计问题

### 网络切换事件丢失

原逻辑 A→B、防抖后发现 C，就把最后处理状态更新为 C，下一轮 C 稳定也不再重连。现在由 `reconcile_underlay_change` 分开 observed/recovered 状态：只有恢复成功才推进 recovered；冷却期间和失败恢复保持 pending，最终稳定后重试。防抖结束还需重新尊重手动停止、模块禁用和官方 APP VPN。

### 配置备份与写入

秒级名称会覆盖同秒备份，单独原子 `mv` 也不足以串行化“备份→保存”。写入/备份统一进入子 Shell 写锁，真正的子进程 PID 通过内建 read 读取 `/proc/self/stat`，信号退出清理自己的锁。确认 owner 已退出后才回收旧锁；缺 owner 不视作死亡。唯一且禁止覆盖的备份名称修复同秒覆盖，保留最近 10 份时明确保留本次新备份。

### WebUI 异步与性能

状态/日志读取原先会被较慢的旧响应覆盖。新增 LatestRequest 合并重复读取并失效过期结果；隐藏页面失效原会话；服务操作后强制新快照。热点失败后的刷新移至解除 busy 之后，历史状态响应不能覆盖新的操作；读回失败显示未确认。配置按钮操作串行化。日志按字面在原文计算高亮，再转义 HTML，避免搜索 INFO 改坏类名。

概览改为单次 `overview` 调用，status/metrics 共享 RPC、上联、端点、PID/TUN 等本轮样本；守护进程保留实时探测。删除日志页第二个轮询入口，配置的 5 秒间隔在 30 秒模拟时段内只触发 6 次读取（此前为 9 次）。模块大小缓存 300 秒并在版本变化/时钟回拨时失效。

### 新增验证

`test-underlay-debounce.sh`、`test-config-write-lock.sh`、`test-overview-snapshot.sh`、`test-webui-requests.mjs` 及浏览器失败场景覆盖上述复现。正常配置迁移、三台设备 profile revision 和默认路由策略不变。

### v1.0.0 发布核验

2026-09-06：最终通用包构建执行完整验证通过，包括 25 项 Shell 回归、请求/日志与拓扑单测、TOML 测试和 Chrome 浏览器失败/并发场景。三个自用包与 beta.24 的网络配置和核心二进制逐字节一致，profile revision 与默认策略未变；新版本为 1.0.0、versionCode=100000。修复后的后端脚本及生成 WebUI 与最终源码构建产物完全匹配。

三个包通过 SSH 发布到飞牛 `<NAS 备份目录>/<版本目录>`，远端 ZIP、说明和模拟数据预览图 SHA-256 全部匹配。通用包保存在本地 `dist/TierNest-v1.0.0-et2.6.4-arm64.zip`。完整验证、包内核验、依赖审计和上传记录位于 `.private/validation-v1.0.0/`。没有远程安装、重启 Android 设备或声称完成升级后的真机联网验证。

配置原文编辑额外修复：重新点击当前 TOML 视图不得把未保存编辑换回旧表单；格式化只序列化当前原文，不填入默认配置项；解析失败不进入可能过期的可视化表单。磁盘配置可读但语法错误时进入原文视图供修复。

## 2026-09-08：FlClash 重复触发恢复、路由重写与网络快照刷屏

证据来自 `TierNest-diagnostics-20260908-181450.txt`（Ace 3 Pro / Android 16 / v1.0.0）。用户确认没有手动停止/禁用，另报告回家后手机发热。

- 17:49:24 FlClash（`com.follow.clash`）创建 tun0；17:49:29 被误认成物理上联变化，17:49:47 重启。17:50:04 RPC、强制 TUN Ping、代理 Ping 和 TCP 探测均正常；17:50:16 又因外部 VPN 变化重启，17:50:17 停止核心后没有启动记录。
- 约 17:58:54 才在快照中出现家庭 Wi-Fi 地址。18:14:51 核心仍停止；此时普通 Ping 和 TCP 通过家庭网络成功，不能算手机 TierNest 在线。家庭 Wi-Fi 不应自动关闭模块。
- 完整网络日志保留 151 个快照，其中 98 个核心已停止。稳定家庭网络下约 12 秒一次完整快照，内容基本相同。`capture_transport_endpoints` 覆盖外层 `network_watch.sh` 的 `signature`，导致网络签名与传输签名反复比较。改为子 Shell 隔离变量，并测试一次真实变化后不再重复采集。
- 完整模块日志有 373 条 `removed=1` 协调。移动数据直连地址期望值是 `198.18.0.2/32`，`ip route show` 输出省略 `/32`；字符串比较误认成多余路由。比较前补齐主机前缀，测试连续协调不增加计数。
- `underlay_signature` 在普通查询落到 VPN 时改查 Android 默认物理网络规则及路由表，再绑定实际网卡查询；没有可确认的默认物理网络就返回 none，不随意选 IMS/其他活动网卡。上联恢复覆盖恢复开始时的 VPN 状态，后续变化仍保持待处理；VPN 自身也采用 observed/recovered 状态避免丢失冷却期或失败事件。
- 主守护进程缺失时允许幸存的 watcher 拉起，明确检查停止/禁用/卸载/官方 APP VPN，检查 PID 对应的脚本参数以防 PID 复用。新 daemon 不得用重复 watcher 的临时 PID 覆盖幸存 watcher 的 PID。
- 诊断增加 daemon/watcher PID、心跳、手动停止标记、恢复阶段和进程等待位置；记录 daemon 退出/信号。旧报告不足以确定第二次重启是卡住还是退出，不能把推测写成已确认根因。没有 CPU/温度数据，也不能把发热全部归因于模块；无后续重启记录，不应解释成“回家后不停重启”。

v1.0.1 保留核心版本、三台设备身份、profile revision 与默认路由策略。自动化验证不能替代手机升级后 Clash 开关、家庭 Wi-Fi 切换、后台稳定性及温度验证。

2026-09-08 本地验证：完整模块检查通过（27 项 Shell 测试、拓扑/请求/TOML 与浏览器集成测试）。新增用例覆盖 VPN 默认路由掩盖物理上联、同时变化合并、冷却/失败重试、恢复期间的新变化、手动停止优先、稳定网络仅采集一次变化、主机路由幂等、PID 复用和存活 watcher 接管。通用与 Ace3Pro-A16 私密 v1.0.1 ZIP 已构建；私密包脚本与源码逐字节一致，配置/核心二进制与 v1.0.0 一致，profile revision 仍为 9，未打包 run/logs。未安装到手机，尚无升级后的真机验证。


## 2026-09-12：小米 10 待机耗电与统一升级包

用户确认禁用 TierNest 后待机续航恢复正常。手机实际运行 1.0.0 / EasyTier 2.6.4 / APatch / Android 17，包名中的 Mi10-A13 只是旧标签。导出脚本确认 `capture_transport_endpoints` 仍是普通函数，会覆盖 watcher 的 signature；当前源码 1.0.1 已有子 Shell 隔离修复。19:20–19:29 的日志保留 37 次完整快照，上联状态一致且 RPC 全部 healthy。同一窗口有 773 次连接失败，其中四个节点约每 3 秒重试。两种活动需分别处理，不能将全部耗电精确归因于某一个，也没有测量硬件漏电。

按用户要求，从 1.0.2 起只发布一个 arm64 通用 ZIP，不再产生小米 10、小米平板、一加或私密设备包。模块 ID 保持 tiernest。旧构建入口拒绝私密参数；无参数时转到统一构建。历史 ZIP 保留，不作为新版本产物。

安装器取消基于 profile revision、hostname、IP 的强制覆盖。先备份旧文件，再从该备份快照继承 TOML、命令参数、路由/热点偏好和手动停止状态，同时继承历史备份。TOML 原样复制，即使为空或暂时无效也不换成另一台设备的配置。新版 settings.conf 只合并仍受支持的旧键，新增键使用新默认；退役的 PREFER_BUNDLED_CONFIG 不再生效。旧 dedicated/镜像路由安装缺少策略键时继承为 legacy。旧设备元数据仅作备份，不参与运行配置覆盖。

复制/合并失败中止安装，旧模块配置不变；继承运行参数不执行旧 Shell 表达式。旧 EasyTier 禁用标记仍区分由 TierNest 禁用和用户原先禁用。统一包只带空白配置和示例，不带私人节点标注、配置备份、运行状态或日志；打包时验证 UNIX 权限、ZIP 完整性与可重复构建，并拒绝私密身份/密钥/设备 profile。

迁移用例覆盖三种旧标签、首次安装、旧策略、空/无效 TOML、命令模式、旧 EasyTier、禁用所有权、源优先级、备份重名、危险表达式与复制失败。Windows Git Bash 的进程启动成本使原 watcher 固定 10 秒测试窗口不可靠，改为等待可观察采样事件与稳定轮询，保留总超时。MSYS socket fixture 使用仿真符号链接；Windows 无 POSIX 权限位，权限由 ZIP 和 Android 隔离演练核验。配置并发测试无 BusyBox 的主机使用另一个独立 Bash 进程。

已在连接的小米 10 的临时目录执行真实 /system/bin/sh 安装器演练，读取本机现有配置后继承到临时 staging：TOML 与偏好逐字节一致、运行参数一致、配置权限 0600；运行中模块的配置/settings 哈希及核心 PID 未变。临时文件已清理。本次没有刷入通用包或重启手机；三台设备实际升级联网与拔线待机效果仍需后续验证。

### 2026-09-12 20:17–20:22：小米 10 用户升级后的实机检查

用户自行覆盖安装并重启后，通过 ADB 确认实际运行 `1.0.2-et2.6.4` / APatch / Android 17。手机 common.sh、network_watch.sh、tiernestd.sh、control.sh 与发布源码逐字节一致；hostname、instance_name、虚拟 IP、network_identity、flags 均与升级前相同，全部仍支持的运行参数保持原值；旧 PREFER_BUNDLED_CONFIG 已退役。升级备份存在于 config/backups/upgrade-20260912-201218-0。

20:15:20 和 20:16:20 的恢复分别对应 Wi-Fi→移动数据、移动数据→Wi-Fi，均完成；20:16:31 启动的核心 PID 24652 至 20:22:30 未再变化，守护进程心跳更新。20:16:28 的一次 RPC timeout 位于核心重启期间，恢复后 healthy，不能当作稳定运行期 RPC 故障。

稳定后完整快照为 20:16:42、20:21:49；后者标记 periodic-300s、RPC healthy。实机已确认不再每个 watcher 周期反复完整采集。ADB 根权限探测：10.42.0.1 正常/强制 tiernest0 Ping 均 0% 丢包，192.168.50.1 Ping 0% 丢包，两者 TCP 80 成功且 HTTP 返回 200。家庭网关走 wlan0，虚拟网关走 tiernest0；没有把本地 LAN 直连当作覆盖网络验证。没有操作普通应用浏览器，因此不把上述结果描述为全部应用联网均已验证。

用户尚未移除之前五个持续失败节点，20:20 的核心日志仍显示这些端点的重试。203.0.113.10:11010 当前传输快照为 ESTABLISHED；其切网期间曾有失败，不等于当前连接失败。检查时手机在充电，不能据此认定拔线待机续航已经恢复。排查期间没有改动配置或重启核心。

### 2026-09-12 20:52：Download 配置备份与实机迁移

用户要求新备份保存到 Download，旧备份真正移走，避免两套文件占用空间。v1.0.3 将手动备份和保存前快照写入 `/sdcard/Download/TierNest/backups/`；首次读取设置、创建备份或保存配置时自动迁移旧目录，包括升级快照。迁移先复制到唯一临时目录，递归比较文件字节和目录条目，再发布到唯一的 `legacy-时间-进程-序号/`，二次核验后删除旧目录；同名 Download 文件不覆盖。新配置备份保留最近 10 份，迁入的历史目录单独保留。没有新增后台轮询。

Android 共享存储由系统决定权限位，不能因 `chmod 0600` 不受支持而把成功写入当成失败。真实手机临时目录验证：备份可创建和读取、历史升级目录与隐藏文件完整迁出、源目录删除、重试不重复、同名目标保留。模拟不可写目标时保存失败且活动配置不变，临时共享存储文件已清理。

在用户已授权的目录修改范围内，现场原子更新了配置 API、control 命令、WebUI 和版本标记，无需刷机或重启服务。安装后的管理器清理了 README.md，现场更新因此只替换实际运行文件。两份历史 TOML 与 upgrade-20260912-201218-0（4 个文件）已迁入 `legacy-20260912-205223-29280-0/`；原 `/data/adb/modules/tiernest/config/backups/` 已删除。新建 `config-20260912-205224-29337-0.toml` 与当前配置一致。迁移前后 config.toml、settings.conf 哈希相同，核心 PID 14043 未变。普通应用文件管理器的浏览操作未代替用户执行；共享存储实际权限为 root:everybody，目录 0770、文件 0660。

本地覆盖配置读写、迁移/重名/失败重试、共享存储 chmod 限制、配置锁与保留数量；13 项统一升级迁移场景和 Chrome WebUI 集成通过，包继续不包含任何手机配置、备份或运行日志。打开已缓存的 WebUI 时需退出重进以加载新的路径提示。

v1.0.3 最终通过统一入口 `scripts/build-module.sh` 完整构建：28 项 Shell 检查、WebUI/拓扑/TOML 与 Chrome 集成、包完整性/权限/可重复性和隐私排除校验全部通过。最终包 SHA-256：`82015ff314c4bc5c95f5344df72fe53aef37628908ae30d0527653d1a0468743`。与 v1.0.2 比较仅配置 API、control、版本/说明和 WebUI 7 个文件变化；common.sh、network_watch.sh、核心二进制和默认配置逐字节不变。手机实际更新的 5 个程序/WebUI 文件哈希与最终发布源码一致，没有待生效的 modules_update/tiernest，现场临时目录已清理。

### 2026-09-12 21:10–21:20：一加 Ace 3 Pro 升级核验与 DNS 残留问题

OnePlus PJX110 / Android 16 / KernelSU v3.3.0。初始 ADB Shell 未获 Root、su 不可见；用户在 KernelSU 为 Shell 授权后正常读取。实际运行 1.0.3-et2.6.4，8 个管理脚本/WebUI 文件与发布源码一致。TOML 与 upgrade-20260912-210406-0 逐字节相同，settings 全部不变，Example-Phone-A、10.42.0.10/24、6 个入口、legacy/dedicated 策略正确继承。

外部 VPN tun0 开启时 9 个远端在线、RPC healthy。ADB 根权限对 10.42.0.1 普通/强制 tiernest0 Ping、192.168.50.1 Ping 均成功，两个地址 HTTP 200；虚拟地址走 tiernest0，家庭网关走 wlan0。21:06–21:09 的 4 次重启均对应真实 VPN 或物理网络变化，11–14 秒完成；核心 PID 9278 随后稳定。完整快照 21:09:51、21:14:50（periodic-300s），未复现稳定期每轮重复诊断。

旧备份尚未触发首次配置操作迁移。按用户已明确要求，调用安装模块的加锁迁移函数，将 1 份普通备份、2 个升级目录共 10 个文件迁入 Download/TierNest/backups/legacy-20260912-211521-24901-0，字节校验后删除旧 config/backups。活动配置、settings 和核心 PID 不变。

残留问题是 tcp://peer-a.example.com:11010、tcp://peer-b.example.com:11010、udp://peer-c.example.com:11010 反复约 2 秒 DNS 超时，每个入口大致 3 秒一次。手机系统解析和 Ping 三个域名均成功，对应 IP 203.0.113.11、203.0.113.12、203.0.113.13 在详细 peer 表中已有 TCP 连接。UDP 域名入口失败不能用同 IP 的 TCP 成功替代验证，也不能称整个节点已失效。未改动用户节点。

核对当前核心提交 8428a89d 的 common/dns.rs：lookup_host 无独立超时，只在返回 Err 后回退 Hickory。症状与上游 Linux aarch64 在 Android 下解析阻塞、连接阶段 2 秒预算先耗尽的问题相符（https://github.com/EasyTier/EasyTier/pull/2310/files）。这是有源码依据的排查方向，不是已完成核心替换对照验证。

21:12:30–21:16:56 两段采样中 easytier-core 单核等效 CPU 为 9.99%、8.29%，RSS 约 278 MiB 且短期稳定；未把守护脚本计入核心占用，也未隔离 DNS 重试的耗电贡献。手机 USB 充电，不能据此认定待机续航恢复。详细报告保存在当前工作区 outputs/TierNest-一加升级检查-20260912.md。


## 2026-09-12：停止后仍有后台与家庭自动待机（v1.0.4）

一加 PJX110 / Android 16 / KernelSU v3.3.0 上，v1.0.3 的停止只写 manual_stop 并停核心；tiernestd 仍每轮清理后 sleep，network_watch 仍采样且可拉起监督器。旧版没有家庭识别逻辑，连接家庭 Wi-Fi 不会自动停机。用户选择新版同时支持手动 / 自动两个模式。

实现 service_api、home_watch 与统一开机入口。生命周期操作与核心启动分别使用带真实 owner PID 的锁；停止先发布标记，再按准确脚本 argv 和 /proc start token 终止进程树，最后清理核心和路由。Android 此内核没有 /proc/PID/task/PID/children，必须使用 ps -A -o PID,PPID 递归查子进程。先冻结父子进程再发 TERM/CONT，并清理尚未退出的进程，避免遗留 sleep、探测器和正在恢复的任务。普通后台在停止/在家暂停时退出，开机入口不会撤销手动停止。

home_watch 每 30 秒检查记住的 WLAN/网关/MAC，HTTP 探测绑定物理 WLAN 且禁用代理，成功后暂停核心和普通监视；网关变化立即恢复，同网关连续两次探测失败恢复。手动停止优先于模式选择及自动恢复。通用包不内置真实家庭信息，新状态文件加入升级快照和继承清单并保持打包排除。

实机独立目录演练：生产开机入口在 manual_stop 下不启动任何后台；真实 Android shell / sleep 子进程树能够整体退出；回收 PID 文件不会杀掉无关 sleep；现有家庭 WLAN 强制路由、网关 MAC 和经 OpenWrt 访问虚拟地址的 HTTP 验证通过。该演练不等同于刷包后的长时间待机和真实出门测试。

真实服务停止/恢复补查发现会话挂断问题：v1.0.3 的后台继承 Root ADB 会话，测试脚本内看到启动成功，但关闭连接后核心与监督器又被挂断。仅将 `(exec setsid ...)` 的括号函数放到后台仍不够，Android mksh 会保留中间 Shell，连接挂断后它继续向独立会话的工作进程转发信号。最终使用 `{ exec setsid ...; }` 花括号函数并只在后台调用，关闭 stdin，等待后台发布真实 PID；核心启动后重新验证实际程序 PID。实机 /proc stat 确认核心和守护的 PPID 为 1、会话各自独立，结束启动连接后另开 ADB 查询仍为 running，RPC healthy、策略规则 9980 正常。第一次“已恢复”仅为连接内结果，最终判断以断开连接后的独立复查为准。

真实停止检查确认核心、守护和网络监视退出、表 20110 的模块策略规则清除，停止的 12 秒内模块/网络/传输日志大小不增长，关闭手机核心后仍可通过 wlan0 访问 OpenWrt 虚拟地址。TOML 与 settings.conf 前后哈希一致。未刷写生产模块文件、未重启手机，生产安装版本仍为 v1.0.3；v1.0.4 启停助手仅用于实机验证，最终恢复原先的手动模式运行状态。

最终独立实机自动循环检查通过：真实 home_watch 脚本在启动连接关闭后继续运行，保持实际 30 秒轮询间隔，以临时文件模拟离家/回家输入、以文件模拟核心状态并屏蔽网络写操作；离家恢复、回家暂停、手动停止后不复活均通过。完整构建通过 29 组 Shell 检查、13 个迁移场景及浏览器/打包验证。最终通用 ZIP SHA256 为 `19db42b4693fc1ef10ec16d22b5da5da5e08a3a1ad4058d25b7f833e189175e0`。


## 2026-09-12：随身 Wi-Fi 也是可替代手机节点的路由器（v1.0.5）

用户补充另一台随身 Wi-Fi 网关 192.0.2.1 也提供子网代理，可以访问 10.42.0.1。实机切换后，一加 wlan0 地址为 192.0.2.210，强制 WLAN 路由为 10.42.0.1 via 192.0.2.1 dev wlan0 table wlan0，网关 MAC 为 02:00:00:00:00:42；绑定 wlan0 的 HTTP 验证返回 200，用时约 0.096 秒。手机核心当时仍在运行，但检查流量强制经随身 Wi-Fi，没有借用手机 TUN。

v1.0.4 只保存一组 interface/gateway/mac/target/port，“在家待机”的界面描述也不适合随身路由器。v1.0.5 改为多个 network= 行，兼容旧单组 key=value 文件且读状态/启动时不改写旧文件。保存新网关时保留其他记录，同一 WLAN/网关 IP/MAC 身份更新验证目标。列表提供独立删除，删除最后一条回到手动模式，保留手动停止优先级。

自动暂停标记记录当前网关 ID。两个可信代理间切换可继续暂停；换到另一网关但其探测失败时不沿用上一网关的失败容忍时间，立即恢复核心。同一网关仍采用两次失败后恢复。自动待机的周期、完整停止和独立进程启动规则不变。

在一加生产配置目录通过服务锁和原子替换保存了两个实测网关，仅新增本机 home-network.conf；随身 Wi-Fi 使用新版 helper 真实验证成功。保存前后 TOML、settings.conf 哈希与核心 PID 16004 不变，独立 ADB 复查 RPC healthy。临时注册脚本与归档已清理。安装版本仍为 v1.0.3，默认手动模式未变；用户刷入 v1.0.5 后继承记录，再自行选择自动模式。通用 ZIP 未包含本机网关或网络状态。

最终通过统一入口 scripts/build-module.sh 完整构建：30 组 Shell 检查、14 个升级迁移场景、WebUI/拓扑/TOML 与 Chrome 集成、包完整性/权限/可重复性及隐私排除检查全部通过。移动尺寸界面已目视检查，发布 ZIP 各文件与 module/ 源码逐字节一致。SHA256：`5ccb2ea998a9cee96305734f0502b16664d0281b7f564ce566efcb5c29aa0f7d`。尚未在安装后的 v1.0.5 上进行真实双 Wi-Fi 切换及长期拔线待机验证。

## 2026-09-12：安装后自动模式失败，执行权限遗漏（v1.0.6）

用户安装 v1.0.5 后选择自动模式显示“操作失败”。一加生产日志为 `setsid: exec /data/adb/modules/tiernest/home_watch.sh: Permission denied`；home_watch.sh、service_boot.sh 和 service_api.sh 实际为 0644，同目录旧脚本 tiernestd.sh 为 0755，SELinux 标签相同。模式已保存为 auto、核心已进入暂停，但监视器未运行；service.sh/boot-completed.sh 直接 exec 的 service_boot.sh 也缺少执行权限。

根因是 customize.sh 手工枚举权限的列表遗漏新增脚本，之前仅检查 ZIP 内的 0755 位无法覆盖管理器解压后重设权限。之前临时目录实机演练提前 chmod 了脚本，也未覆盖真实安装权限。v1.0.6 将安装器改为覆盖全部根目录 Shell 脚本，新增从 0644 初始权限执行真实安装脚本的回归，覆盖开机/自动/普通后台入口和未来新增脚本，同时检查配置保持 0600。新回归在旧安装器下复现 service_boot.sh=0644，修改后通过。

现场仅把这台一加三个遗漏脚本设为 0755，然后重新应用用户已选择的自动模式，返回 0。独立 ADB 查询确认 home_watch PID 28861、PPID 1，模式 auto、当前代理为随身 Wi-Fi，核心及普通守护未运行；强制 wlan0 HTTP 探测仍为 200。TOML 与 settings.conf 哈希和修复前一致。设备版本标记保留 v1.0.5，修复即时生效；没有重启手机，也未改变 30 秒检测间隔。长期待机及重启后的行为仍需实机观察。

进一步在手机隔离临时目录把所有文件重置为 0644，再用真实 Android chown/chmod 执行新版安装器，确认所有根目录 Shell 脚本为 0755、配置为 0600；生产配置哈希不变，临时文件已清理。修复后的真实 service.sh 开机入口返回 0，复用现有自动监视器，没有重复启动；多次独立复查 PID 28861 存活，tiernest.log 保持 231 字节，没有新增权限错误。本次没有重启手机。

完整构建通过 31 组 Shell 检查、14 个升级迁移场景及 WebUI/浏览器/包校验。最终 v1.0.6 ZIP 与 v1.0.5 相比仅 customize.sh、module.prop、README.md 三个文件变化，运行脚本、WebUI、核心和默认配置逐字节一致。SHA256：`276a6b6b68c281a3cc207586e68b7edd6cc89339c130765c911227988cd35d6b`。修复后状态命令用时 3 秒、返回 0，报告 service_mode=auto、home_paused=1、home_watch_pid=28861、rpc_state=stopped，符合路由器代理可用时核心暂停的状态。

### v1.0.6 在一加的真实覆盖安装

随后用户明确授权通过 USB 刷入并测试，计划其余两台也使用同一包。使用设备现有 KernelSU 3.3.0 的 ksud module install 调用正式安装器，返回 0，日志为 Module installed successfully。modules_update/tiernest 中版本 1.0.6、21 个程序/核心/WebUI 文件哈希与发布源码一致，根目录脚本全部 0755、活动 TOML 0600。待生效配置与刷前清单逐项一致，包含 TOML、运行参数、节点标注、路由偏好、自动模式、两个网关记录以及未设置的手动停止标记；现有 Download 备份逐文件哈希不变，新增 upgrade-20260912-232106-0 快照。

已发出真实 reboot 并看到 ADB 重连，随后 USB 再次断开，未能读回重启后的版本、进程及日志。用户在手机端反馈“好像进入自动待机了”；这是用户观察，不等同于已完成 ADB 重启后核验。审计清单和安装日志暂保留在手机 /data/local/tmp/tn106-upgrade-audit，待重连后完成检查与清理。本次尚未操作另外两台设备，用户随后询问自行升级方式。

## 2026-09-13：自动检测方式与自定义间隔（v1.1.0）

自动模式可以选择“定时检测”或“事件检测”。未保存新偏好时保持 poll / 30 秒；新文件 home-detection.conf 仅包含方式和秒数，以原子替换保存。安装器对它执行升级前备份与逐字节继承，通用 ZIP 排除该文件。手动停止不能被保存偏好、切换方式、开机或事件恢复取消。

定时模式继续核对网关身份并通过 Wi-Fi 验证 HTTP，同一网关连续两次失败后恢复。事件模式只在首次添加网络时验证 HTTP，后续按保存的网关 IP/MAC 判断；未知邻居 MAC 可在网络事件后探测本地网关一次，不探测远端虚拟网络。Wi-Fi 不断而路由器代理失效属于该模式明确放弃的自动故障恢复场景，界面必须如实提示。

原生 tiernest-netwatch 同时订阅 RTNETLINK 与 nl80211 MLME；后者覆盖漫游时 IP/接口状态未变的情况。只处理 WLAN 链路、IPv4 地址、默认路由和连接/断开/漫游，忽略扫描结果、普通链路重复通知及 TierNest 的子网路由写入。通知合并约 500ms，管道最多保留一条未读变化通知。Shell 仅在启动/变化后执行有限补查，之后阻塞等待，不能悄悄加入固定间隔轮询。

监听器通过 --check 预检；实际启动还需就绪握手。不能仅依据 home_watch PID 存在就报告监听已经可用。检测进程作为 home_watch 子进程，由原有完整进程树停止逻辑回收；退出时移除 FIFO、PID、就绪标记和锁。监听源异常退出必须撤销自动暂停、恢复正常核心并显示错误，始终尊重手动停止。保存新设置但启动失败时恢复之前的偏好。

回归覆盖事件解码/坏包、静止时无周期检查、配置的实际休眠间隔、监听失败、阻塞子进程回收、运行与停止状态下切换、HTTP 调用差异、非法间隔、原设置回滚、升级备份继承、包内排除及浏览器输入/失败/互斥。测试使用合成网络数据；纯软件环境不能替代物理 Wi-Fi 连接/漫游、厂商权限和长期待机功耗检查。


## 2026-09-19：App 双模式、系统 VPN 与详细节点信息

App 0.2.0-alpha03 增加可选系统 VPN 后端。新安装默认 VPN，升级保留原 Root 选择、
配置原文与家庭偏好。VPN 模式不执行 Root 命令；系统授权、撤销和两种后端的停止
统一由串行连接服务处理。连接失败时先持久化停止状态，再发布 UI 状态，修复按钮
可能短暂保留“断开并停止”的问题。原模块通用升级与网络快照变量隔离代码继续保留。

VPN 使用源码构建的 JNI EasyTier，App UID 排除在自身 VPN 外，防止传输套回隧道。
动态路由增加时可能换 TUN；上游异步接收 FD，因此新接口必须等待 TunDeviceReady
确认后再关闭旧 FD。失败时先停止内核再释放两个描述符，避免 FD 复用与悬空访问。

云手机首次授权后出现 `Cannot create interface`，系统日志为
`VpnJni: Cannot allocate TUN: Bad file descriptor`。测试容器只有 `/dev/net/tun`，
缺少 Android 所用的 `/dev/tun`；临时补齐入口后系统 VPN 与真实 P2P 正常。
普通测试 App UID 访问合成代理子网及物理网络均得到 HTTP 200。
这不代表实体 arm64 Root 授权、Clash 共存或长时待机功耗已通过。

节点拓扑只表达本机路由视角，不伪造全网连接。节点 ID/地址用于下一跳匹配，
未知、折叠多跳及子网用虚线；原始时延是下一跳 RTT。新增模式保留、配置副本、
歧义/环路/撤回和未知 hop 数据回归，JVM 共 25 项通过，Root 回归 14 项通过。

## 2026-09-19：发布 APK 的编译路径隐私检查

源码脱敏和去除原生符号表不代表发布二进制没有本机路径。Rust 依赖中的
`file!()`、panic 和断言位置仍可能包含构建机主目录。重新检查 alpha03 时发现
该类路径，已先下架 APK 附件；没有发现私人网络密钥、真实端点或配置备份被打包。

alpha04 构建对 Rust 使用 `--remap-path-prefix`，对 C/C++ 使用
`-ffile-prefix-map`，将构建机与仓库路径映射到固定的 `/build/`
路径。新增 APK 解包检查，覆盖两个 ABI 的原生库和 DEX，检查开发者路径、私钥、
令牌及私人运行目录；检查失败时构建不能复制或发布 APK。回归包含压缩 APK 内
残留路径、其他开发者路径、私钥与备份目录以及已映射路径。

## 2026-09-19：App 家庭 HTTP 检测被自身组网路由误导

alpha04 通过 `Network.openConnection` 绑定物理网络，但 Android 的网络标记
仍可能被更早的 Root 策略路由覆盖。隔离命名空间复现：带网络标记的请求命中
`tiernest0`；显式限定 `wlan0` 后才经合成网关到达目标。手机自己的核心能访问
虚拟地址，不能作为家庭路由器已提供代理的证据。

alpha05 增加一次性原生 HTTP 探测，使用 `SO_BINDTODEVICE` 和本机 Wi-Fi IPv4
双重绑定；核对地址确实属于该接口，拒绝目标为手机自身地址。连接、发送和读响应
共用 2.5 秒截止时间；无代理、DNS 或重定向。探测前后复核网关 MAC，App 再核对
Network、接口、网关和源地址。检测不增加或删除任何路由，不产生常驻探测进程。

原 Root 命令封装在任意检查错误时关闭会话，连带清理正在运行的核心。现在只有
已经完整读取回复的只读检测错误保留会话；协议、I/O 或取消仍清理，连接服务会
识别已退出的核心并按当前请求恢复。检测错误显示在概览，手动停止仍具有最高优先级。

旧家庭记录和导入记录保留所有身份与目标字段，但需要在对应 Wi-Fi 重新验证一次。
未验证前保持核心运行并显示提示，不自动更改事件/定时模式、间隔或自动开关。
事件模式仍无周期 HTTP；连续同网关的定时检测只容忍一次失败，切网或异常撤销容忍。
原模块的配置继承、备份迁移和网络快照隔离逻辑未修改。

合成网关与隧道的 Android Root 网络命名空间回归验证了：仅隧道可达时失败、真正
Wi-Fi 可达时成功、HTTP 401 可达、畸形响应/慢响应/拒绝连接失败、地址变化/本机目标
拒绝以及 IPv4 路由与规则不变。新增 JVM 信任状态和旧记录回归；真实家庭 Wi-Fi、
实体 arm64 Root 管理器和长期待机功耗尚未验收。

## 2026-09-20：App 后台中断后按钮仍为停止、磁贴变成实心方块

旧 App 将持久化的 `requested` 同时当作用户意愿和服务存活证明。进程结束后，
新进程的概览已经显示「已断开」，磁盘里仍是 requested=true；用户第一次点按钮
实际只清除了旧请求，第二次才能连接。偏好同步还依赖 phase 文案变化，重复出现
同一种失败时可能不刷新。已在没有运行服务的旧版中复现此状态组合。

alpha06 将请求状态作为独立 StateFlow 订阅，在用户打开 App/磁贴时核对服务与
正在启动的请求。孤立旧请求被归档为中断，立即显示「重新连接」。启动请求有一次性
超时保护；正常待机仍有服务所有者，不能误判为退出。异常销毁及时撤销状态，
核心错误和系统退出原因保存在本机。Android 11+ 仅查询对应 PID、晚于该次连接
开始时间的本应用退出记录，缺少证据时显示未知。

服务改为向系统请求 sticky 恢复，手动停止与失败仍先持久化 requested=false，
避免旧意图或恢复回调重新连接。Android 15 模拟器测试 SIGKILL 后 8 秒内没有自动
恢复，因此不能宣称自动恢复必然发生；已验证重新打开后一次重连可建立真实 VPN
接口，强制停止后的重连和错误提示也通过。明确停止后再结束进程不会重启连接。
这不证明用户实体设备先前自动停止的具体原因，需新版退出记录才能进一步判断。

磁贴/通知原来复用带实心底板的桌面 vector，单色染色会覆盖内部图形。改为独立的
透明底三节点符号。桌面图标由用户授权的 Image API gpt-image-2.5 生成，原图与提示词
保存在 output/imagegen，生成凭据和服务 URL 不进入仓库；适配圆形/圆角方形及单色主题。

星际配色改用单个移动选中底板，与底部导航共用 damping=0.85、stiffness=420 的
弹簧。强调色共用 250ms 颜色过渡，快速选择会从当前值继续；减少动态效果时去除
位移。云手机快速换色采样 95 帧、2 帧 jank，p50=8ms、p90=12ms；软件渲染模拟器
明显更慢，不能用这些环境的数字承诺实体手机帧率。

## 2026-09-20：设备名称留空仍广播 localhost

配置页原先提示「留空使用系统名称」，但生成运行副本时没有读取 Android 的友好
设备名。EasyTier 2.6.4 未配置 hostname 时直接调用操作系统 gethostname，Android
通常返回 localhost，导致不同客户端在节点列表里同名。

alpha07 在 Root/VPN 启动与校验时读取 Settings.Global.DEVICE_NAME；缺失或为
localhost 等占位名时回退到 Build.MANUFACTURER / MODEL，品牌不重复拼接。
仅填入缺失或空白的运行副本字段，保留原 TOML 及显式指定的名称，包括显式 localhost。
非字符串 hostname 仍报配置错误，不能被默认值掩盖。自动名称按上游规则限制为
32 个 Unicode 字符，不截断 emoji 的代理对，不读取序列号、Android ID 或蓝牙信息。

新增 7 项回归覆盖系统名称优先、型号回退、Unicode 长度、双模式运行副本、显式
名称保留、空名称和无效类型。合成 Android 设备名通过真实 EasyTier P2P 发送给
独立测试节点，并由对端 CLI 读回；连接前后原始 TOML 字节一致。界面显示实际
自动名称预览。远端原有 localhost 需在对应设备改名或升级后重新连接。

## 2026-09-21：本机诊断导出与 Root 管道异常处理

用户补充实体手机在最新版 Root 模式、没有操作时出现可见闪退，但暂时无法接入 ADB。
现有云手机退出记录只有测试强停与升级，没有该实体设备的堆栈，因此不能把先前
中断归因于系统省电、VPN 核心或某个特定异常。先新增持续本机记录与手动导出能力。

alpha08 在 Application 初始化时注册链式未捕获异常处理器：先写入版本、时间、
异常类型与代码栈，再调用原 Android 处理器正常终止，不吞异常维持损坏进程。
事件采用有界异步队列，磁盘最多保留三份 256 KiB 文件与最近一份崩溃记录；没有
新增加后台轮询、网络请求或 Root 权限要求。可在设置中关闭、清空、通过系统文件界面导出。

不调用全量 logcat，不复制核心原始日志或配置。异常 message/toString、cause 和
suppressed 的消息都可能包含密钥或端点，因此只输出类型和有限代码栈。报告附带
本应用系统退出码与内存摘要、APK 哈希；对应 R8 映射按版本/哈希保存在构建机的
持久数据目录，避免被构建缓存清理。Java 处理器不能捕获原生信号或系统强杀。

代码审查确认 RootSession 的独立 launch 读管道没有捕获 IOException；SupervisorJob
并不能阻止未处理的子协程异常交给 Android 默认崩溃处理器，参见
[Kotlin 异常处理说明](https://kotlinlang.org/docs/exception-handling.html#exceptions-in-supervised-coroutines)。
替换为有界输出读取器后，读错误通过命令通道传给调用者，正常关闭/取消不作为闪退。
故障注入回归确认读错误不会成为未捕获异常，超长行受限，EOF/CRLF 和取消均保持
正确语义。这是一个真实异常处理缺口，但仍不能证明它就是用户那次闪退的根因。

同时发现 Root 命令内部 withTimeout 抛出的 TimeoutCancellationException 被服务当作
生命周期取消重新抛出，可能结束控制循环却保留 requested/前台服务状态。改为只把
自身截止时间转换为 RootCommandTimeoutException，父协程取消仍正常传播；失效的
半截响应会关闭会话，不能被下一条命令复用。这与真正的 Java 闪退是不同的故障路径。

本轮新增 11 项 JVM 回归覆盖消息隐私、因果链界限、轮换/重开/清空、崩溃处理器委托、
Root 管道错误/EOF/长度/取消以及超时与父取消的区分。测试机使用 am crash 主动触发 Java 崩溃，确认
崩溃记录落盘、重开后可导出 TXT，包含调用栈而不包含原始异常消息；关闭并清空后
前后台切换不会继续追加记录。实体手机实际闪退仍待用户导出的日志进一步定位。
