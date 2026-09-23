<div align="center">

<img src="output/imagegen/tiernest-icon.png" width="128" alt="TierNest 图标" />

# TierNest

**独立的 Android EasyTier 组网应用**

VPN / Root 双模式 · 原生 Compose 界面 · 实时节点拓扑 · TOML 配置管理

[![Release](https://img.shields.io/github/v/release/Autsunset/TierNest?include_prereleases&style=flat-square&label=%E5%8F%91%E5%B8%83)](https://github.com/Autsunset/TierNest/releases)
[![Platform](https://img.shields.io/badge/platform-Android%208.0%2B-3ddc84?style=flat-square&logo=android&logoColor=white)](https://github.com/Autsunset/TierNest/releases)
[![EasyTier Core](https://img.shields.io/badge/EasyTier%20Core-2.6.4-ff6f00?style=flat-square)](https://github.com/EasyTier/EasyTier)
[![License](https://img.shields.io/badge/license-LGPL--3.0-blue?style=flat-square)](LICENSE)

[下载最新版](https://github.com/Autsunset/TierNest/releases) · [快速上手](#下载与安装) · [从源码构建](#从源码构建) · [文档](#文档) · [更新日志](CHANGELOG.md)

</div>

---

## 项目简介

TierNest 将 [EasyTier](https://github.com/EasyTier/EasyTier) 异地组网带到 Android，是一个原生 Jetpack Compose 独立应用，支持无需 Root 的 **VPN 模式**与让出 VPN 槽位的 **Root 模式**，不需要先刷入模块。

> **通用 Root 模块已停止发布。** 模块最终版本为 1.1.0，仓库保留其源码与文档，已安装用户可继续使用；建议参考下文[从 Root 模块迁移](#从-root-模块-已停止发布迁移)把配置导入 App 的 Root 模式。

TierNest 是社区项目，与 EasyTier 上游没有官方隶属关系。

## 版本速览

| | 独立 App | Root 模块（已停止发布） |
| --- | --- | --- |
| 当前版本 | 0.2.0-rc02 | 1.1.0（最终版） |
| 发布状态 | 持续更新（候选版） | 不再提供新版本 |
| 系统要求 | Android 8.0+ | arm64 Root 设备 |
| 支持架构 | VPN：arm64 / x86_64；Root：arm64 | arm64 通用 ZIP |
| 管理入口 | App 界面（含快捷磁贴、前台通知） | KernelSU WebUI |

## 运行模式

| | VPN 模式 | Root 模式 |
| --- | --- | --- |
| 前提条件 | Android 系统 VPN 授权 | App 的 Root 授权、TUN、策略路由与 iptables owner 支持 |
| 与其他 VPN 共存 | 占用系统 VPN 槽位，不能同时开启 Clash 等 VPN 模式 | 让出 VPN 槽位；实际共存仍受系统路由、透明代理和厂商防火墙影响 |

组网只接管 IPv4 组网目标与节点发布子网，不提供全局出口或 IPv6 虚拟路由；Root 模式可选择让 Wi-Fi 热点设备单向访问组网，普通互联网流量继续走物理网络。新安装默认 VPN 模式，早期 Root 版升级保留原模式；切换模式保留配置并先断开。

## 功能特性

### 组网与监控

- **概览仪表**：连接状态、运行模式、虚拟地址、节点数、当前网络、连接时长、实时速率、累计流量、路由与采样时间。
- **节点拓扑**：按实际路由绘制拓扑图，列表与拓扑视图切换；点按节点查看下一跳、RTT、节点 ID、版本与共享网段；未知或折叠路径以虚线表示。
- **配置管理**：基本 / 节点 / 参数 / TOML 分组编辑，保留未知字段，先校验后原子保存；原始 TOML 始终是配置权威。
- **自动备份**：保存前自动备份到 `Download/TierNest/backups/`，唯一命名、逐字节校验、不覆盖已有文件。

### 外观

- **三种主题**：星际控制台、Material 3、Miuix 澎湃，明暗跟随系统或独立设置。
- 系统字体与自有品牌素材，支持减少动态效果；磁贴、通知与单色主题图标适配 Android 自适应裁切。

### 可靠性与省电

- **中断恢复**：进程被回收或异常退出后显示「重新连接」，一次点按即可重试；Android 11+ 读取系统退出原因，区分内存回收、崩溃、信号与用户停止。
- **家庭网络待机**（Root + 自动模式）：记住家庭路由器、随身 Wi-Fi 等多个网络，连上可代理的 Wi-Fi 后核心自动待机，离开时恢复；支持匹配网关身份的事件检测（不持续发送 HTTP 探测）与可自定义间隔的定时 HTTP 检测。
- **按需采样**：概览 / 节点页面可见时才连续采样，后台每 60 秒维护动态路由；不持有唤醒锁或唤醒闹钟。
- 手动停止始终优先于网络回调、开机恢复与自动检测；锁屏暂停、开机恢复等省电选项默认关闭。

### 隐私

- 诊断日志默认仅保存在本机，可关闭、清空或手动导出，不会自动上传。
- 诊断报告不收集 TOML、网络密钥、节点名称与地址、家庭 Wi-Fi 身份或原始 Root 输出。

## 下载与安装

### 独立 App

1. 从 [GitHub Releases](https://github.com/Autsunset/TierNest/releases) 下载 APK 并安装；
2. 填写网络名称、密钥、节点 URI，选择 DHCP 或静态 IPv4，保存后连接；
3. VPN 模式首次连接会弹出系统 VPN 授权；Root 模式由 Root 管理器对 **App** 授权（仅 `adb shell` 能提权不等于 App 已获得 Root）。

### 从 Root 模块（已停止发布）迁移

模块不再提供新版本发布，已安装用户可继续使用最终版 `TierNest-v1.1.0-et2.6.4-arm64.zip`。建议迁移到 App 的 Root 模式：

1. 先在原 TierNest WebUI 停止服务，再到 Root 管理器停用旧模块，避免重复内核和路由；
2. 在 App「设置 → 备份与迁移」完整导入旧模块快照，包括 TOML、命令参数、设置、家庭记录与历史备份；原模块不会被修改或删除；
3. 不能等价迁移的 command_args、路由策略和热点设置会要求审阅确认，不执行旧设置中的 shell 内容。

模块的安装、升级、管理功能与文件说明仍保留在 [module/README.md](module/README.md)。

## 从源码构建

```sh
# 独立 CI 测试包：独立包名与签名
./scripts/build-android.sh --ci

# 通用 Root 模块 ZIP（模块已停止发布，源码仍在仓库）
./scripts/build-module.sh
```

App 构建环境：Linux x86_64、JDK 17、Android SDK 36、NDK `28.2.13676358`、Rust `1.95.0`、clang/libclang、curl、unzip、Python 3。脚本会运行 Root 回归、JVM 测试、Lint、双架构 VPN 源码编译和 R8 优化构建，上游下载与依赖校验值均已固定。

> 官方发布使用测试签名密钥，密钥不入库。自行构建的 APK 签名不同，覆盖安装前请先导出配置；GitHub Actions 构建产物用于代码验证，不替代维护者发布包。

完整说明见 [android/README.md](android/README.md)、[native/vpn/README.md](native/vpn/README.md) 与 [开发注意事项](开发注意事项.md)。

## 文档

| 文档 | 内容 |
| --- | --- |
| [android/README.md](android/README.md) | App 使用、诊断日志、配置与备份、构建、验证范围 |
| [android/PLAN.zh-CN.md](android/PLAN.zh-CN.md) | App 方案与验证记录 |
| [module/README.md](module/README.md) | 模块安装升级、管理功能、文件与命令（模块已停止发布） |
| [CHANGELOG.md](CHANGELOG.md) | 版本历史 |
| [TierNest-故障与踩坑记录.md](TierNest-故障与踩坑记录.md) | 故障与踩坑记录 |
| [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) | 第三方组件与许可声明 |

## 已知限制

- 组网接管与路由保护当前只覆盖 IPv4，默认不接管出口节点路由；确需 EasyTier Exit Node 时可在模块 `settings.conf` 设置 `ALLOW_EXIT_ROUTES=1`，但可能与其他 VPN 冲突。
- VPN 模式占用系统 VPN 槽位；Root 模式与 Clash 等的实际共存仍受系统路由、透明代理和厂商防火墙限制。
- 事件检测信任首次验证的网络：Wi-Fi 保持连接但路由器代理故障时不会自动恢复手机核心，需要持续验证时请选择定时检测。
- App 处于候选发布（rc）阶段，当前为测试签名包；真实设备上的待机功耗、Root / Clash 共存与重启恢复仍需持续实测，参见[验证记录](android/PLAN.zh-CN.md)。

## 反馈与参与

遇到闪退或断连，请重新打开 App，进入「设置 → 诊断日志 → 导出诊断日志」，在系统文件界面选择保存位置，把 TXT 文件附带到 [Issue](https://github.com/Autsunset/TierNest/issues)。不需要 Root 或额外的存储权限。

参与开发前建议先阅读 [开发注意事项](开发注意事项.md) 与 [AGENTS.md](AGENTS.md)，了解构建、验证与文档约定。

## 致谢

- [EasyTier](https://github.com/EasyTier/EasyTier) — 组网核心（v2.6.4）。
- [Miuix](https://github.com/compose-miuix-ui/miuix) — 澎湃风格 UI 组件。
- [interstellar-proxy](https://github.com/zn0wii/interstellar-proxy) — 星际控制台主题的视觉参考。
- [tomlj](https://github.com/tomlj/tomlj) — TOML 解析。

完整的第三方组件、版本与许可声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 许可

本项目以 [GNU LGPL-3.0](LICENSE) 发布。EasyTier 核心是独立的 LGPL-3.0 程序，随包分发的二进制保持未修改；VPN 后端通过 LGPL-3.0 JNI 桥接源码构建的 EasyTier 库，替换与重编译说明见 [native/vpn/README.md](native/vpn/README.md)。

TierNest 是独立社区项目，与 EasyTier 上游没有官方隶属关系，也未获其背书。
