# TierNest Android App

**0.2.0-alpha05** · Android 8.0+ · Kotlin / Jetpack Compose · EasyTier 2.6.4

独立组网 App，可在首页选择 **VPN 模式**或 **Root 模式**。不需要先刷入模块。
新安装默认 VPN；从早期 Root 版升级保留原模式、TOML、主题和运行偏好。

| 模式 | 要求 | 与其他 VPN 共存 |
| --- | --- | --- |
| VPN | Android 系统 VPN 授权；arm64 或 x86_64 | 占用系统 VPN 槽位，不能同时开启 Clash 的 VPN 模式 |
| Root | arm64、App 的 Root 授权、TUN、策略路由、iptables owner 支持 | 让出 VPN 槽位；实际效果仍受 lockdown、透明代理和厂商防火墙影响 |

VPN 模式的内核、校验、配置保存和 Download 备份不调用 `su`。连接期间切换模式会
先断开，随后由用户重新连接。系统撤销 VPN 授权时停止内核，不无限重试。
只接管 IPv4 组网目标与节点发布子网，不提供全局出口、IPv6 虚拟路由或热点转发。
普通互联网流量继续走物理网络。

## 功能

- **概览**：连接状态、模式、虚拟地址、节点数、当前网络、连接时长、实时速率、累计流量、路由和采样时间。
- **节点**：列表与路由拓扑切换，点按查看下一跳、RTT、节点 ID、版本和共享网段。
  根据实际路由画图，未知/折叠路径用虚线表示；它不是整个 Mesh 的物理连接地图。
- **组网**：基本、节点、参数、TOML 分组编辑；保留未知字段、校验、导入、备份、保存并应用。
- **外观**：星际控制台、Material 3、Miuix 澎湃；系统/浅色/深色可独立设置。
  控制台底栏参考 interstellar-proxy 的弹簧位移与颜色过渡，支持快速改选。
  系统字体、自有品牌，没有厂商字体或品牌素材；支持减少动态效果。
- **启停**：前台通知、通知停止、快捷磁贴，手动断开优先于网络回调及开机恢复。
- **省电选项**：默认关闭的锁屏暂停与开机恢复；锁屏暂停会中断传输，亮屏重新连接。
  Root 模式另支持已验证家庭 Wi-Fi 的事件/定时检测待机，HTTP 默认 30 秒。
- 概览/节点可见时才连续采样；后台连接每 60 秒维护动态路由。
  事件家庭待机不安排重复 HTTP，手动停止退出服务。不持有唤醒锁或唤醒闹钟。

## 安装使用

从 [GitHub Releases](https://github.com/Autsunset/TierNest/releases) 下载 APK。
填写网络名称、密钥、节点 URI，并选择 DHCP 或静态 IPv4，保存后连接。
VPN 模式首次弹出 Android 授权；Root 模式由 Root 管理器授权 **App**。
仅 `adb shell` 能提权的环境不等于 App 已获 Root。

使用 Root 模式前，先在原 TierNest/EasyTier WebUI 停止服务，再在 Root 管理器停用
旧模块，避免重复内核和路由。停用模块本身不会终止已经运行的进程。

## 家庭网络待机

仅在 **Root + 自动模式**生效。先连到已提供 EasyTier 代理的家庭 Wi-Fi，在
「设置 → 家庭网络」填写经路由器可访问的虚拟 IPv4 和 HTTP 端口，验证并保存。
再到「运行与省电」选择自动。手动断开始终优先，离家不会自行取消手动停止。

alpha05 的短时探测程序同时绑定 Wi-Fi 网卡和其当前 IPv4，避免高优先级手机
组网路由绕过 Android `Network` 绑定；验证前后复核网关身份和网络信息。
目标不能是本机地址；HTTP 验证不跟随重定向、不借用代理、不修改系统路由。
检测异常保留或恢复核心，并在概览显示原因。

升级和模块导入保留家庭记录、目标、模式与间隔。旧记录会显示「需要重新验证」，
连回对应 Wi-Fi 后点「重新验证」即可；验证成功前不会用旧记录进入自动待机。
事件模式在验证保存后只匹配网关身份，不重复 HTTP；Wi-Fi 不断而路由器代理失效
时无法自动发现。定时模式默认每 30 秒验证，同一连续连接允许一次短暂失败，
第二次失败恢复核心。切网、地址变化或检测异常会清除这次失败容忍。

## 配置与备份

原始 TOML 是配置权威，运行时生成单独副本，升级不会用模板替换私人网络。
所有更改先校验；替换旧配置前必须成功备份，再原子保存。
备份保存在 `Download/TierNest/backups/`，唯一命名、逐字节校验，不覆盖已有文件。
VPN 模式在 Android 10+ 使用 MediaStore；Android 8/9 需要文件存储权限。

Root 模式可在「设置 → 备份与迁移」完整快照导入旧模块，包括 TOML、参数、设置、
家庭记录、停止状态和历史备份。原模块不修改或删除。不能等价迁移的 command_args、
路由策略和热点设置要求用户审阅；不执行旧设置中的 shell 内容。旧模块的备份迁移
功能继续独立保留，App 导入增加快照以供回退。

## 构建

Linux x86_64、JDK 17、Android SDK 36、NDK `28.2.13676358`、Rust `1.95.0`、
clang/libclang、C/C++ 工具链、curl、unzip、Python 3。先设置 `ANDROID_HOME`。

```sh
rustup toolchain install 1.95.0 --profile minimal
rustup target add --toolchain 1.95.0 aarch64-linux-android x86_64-linux-android
sdkmanager 'platforms;android-36' 'build-tools;36.0.0' 'ndk;28.2.13676358'
./scripts/build-android.sh
```

脚本运行 Root 回归、JVM 测试、Lint、双架构 VPN 源码编译和 R8 优化构建。
输出 `dist/TierNest-App-v0.2.0-alpha05.apk`。上游下载、Cargo 依赖、工具版本和
Gradle 分发包校验值已固定。VPN 编译与修改说明见 [native/vpn](../native/vpn/README.md)。

这是 Release 优化的 **alpha 测试签名包**，保持早期测试包的覆盖升级能力。
签名密钥不进入仓库。自行构建/CI 的签名不同，改装前先导出配置；不应直接覆盖
来自不同签名的安装。GitHub Actions 构建产物用于代码验证，不替代维护者发布包。

## 验证范围

参见 [方案与验证记录](PLAN.zh-CN.md) 及 [故障记录](../TierNest-故障与踩坑记录.md)。
云手机可验证界面与 VPN 功能，不能替代 arm64 Root 授权、Clash 共存、真实移动网络、
待机耗电和重启的完整验收。连接时 EasyTier 心跳与打洞仍会耗电，不承诺零耗电。

家庭探测的网络隔离回归需授权的 Root Android 测试设备：

```sh
bash tests/test-home-probe-device.sh <adb-serial>
```

该回归在临时网络命名空间中创建合成 Wi-Fi/隧道和 HTTP 服务，验证隧道误判隔离、
真实网关可达、超时、无效响应、本机目标拒绝和路由不变；退出后清理测试进程与文件。
它不替代实体家庭 Wi-Fi 的连接、漫游和离家验收。

## 来源与许可

TierNest 是独立社区项目，采用 LGPL-3.0。内核来自固定版本 EasyTier，界面参考
[interstellar-proxy](https://github.com/zn0wii/interstellar-proxy)，澎湃组件来自
[Miuix](https://github.com/compose-miuix-ui/miuix)。许可证与来源见
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)。MoonTier 仅作为功能参考，未复制其代码或二进制。
