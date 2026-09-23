# Android 构建与发布

维护者分发 APK 与 CI 验证包使用不同身份。正式版的准入条件见
[App 发布计划](APP_RELEASE_PLAN.md)。目前目标为 `0.2.0-rc03`，实体设备验收完成前
保持候选标记。

## 普通开发与 CI

```sh
bash scripts/build-android.sh --ci
```

此模式生成 `com.tiernest.app.ci` / 「TierNest CI」，版本附带 `-ci`，输出到
`dist/TierNest-CI-v<version>-ci.apk`。CI 密钥自动保存在构建机的
`${XDG_CACHE_HOME:-$HOME/.cache}/TierNest/ci-signing/`，从不复用维护者证书。
CI 包可以与维护者包并存；两者配置分别保存。不要同时启动两个 Root 实例，Root
会话锁仍只允许一个实例管理自有路由。

GitHub Actions 只使用此模式，保持 `contents: read`，动作版本固定到提交 SHA。
仓库没有发布私钥或私钥密码，流水线不执行发布上传步骤。参见
[GitHub Actions 安全使用说明](https://docs.github.com/en/actions/reference/security/secure-use)。

## 维护者签名

默认读取仓库外的
`${XDG_DATA_HOME:-$HOME/.local/share}/TierNest/signing/release.properties`，或通过
`TIERNEST_SIGNING_PROPERTIES` 指定文件。所需属性为 `storeFile`、`storePassword`、
`keyAlias`、`keyPassword`。目录权限设为 `0700`，文件与密钥库设为 `0600`。
不要在命令行参数、CI 日志或仓库文件中填入真实密码。

维护者密钥库保留 alpha 版本已使用的私钥和证书身份；重新加密保管并更换别名不会
改变安装签名。历史证书名称保留，以兼容已有安装。禁止直接生成另一把钥匙替换
它：签名改变可能破坏覆盖升级。发布证书 SHA-256 固定于
[release-cert.sha256](../android/release-cert.sha256)。参见
[Android 应用签名说明](https://developer.android.com/studio/publish/app-signing)。

```sh
bash scripts/build-android.sh
```

缺少私有配置时，发布构建会停止。Gradle 的 release 打包任务也检查签名配置，
不会静默回落到 SDK 默认 debug 密钥。用户配置不会因签名工程调整而迁移或重置。

## 自动检查

构建入口运行 JVM、Root、热点和隐私回归以及 release Lint。产物检查实际 APK 的：

- 包名、版本名和版本码与所选模式及版本源一致；
- 签名与维护者证书相符，或 CI 签名明确不同；
- 非调试标志、Android API 范围及 arm64/x86_64 两种 ABI；
- 原生 ELF 段的 16 KiB 对齐，以及 APK ZIP 对齐；
- 三个 Root 二进制的完整校验清单；
- 不含开发者路径、私钥或私有运行文件。

每个 APK 旁生成 `.verification.json`；它只含包与校验信息，不含私钥路径或密码。
对应 R8 映射按版本和 APK SHA 保存在持久目录，不随构建缓存清理。

## 发布候选包

1. 运行本地检查和适用的设备测试，在发布计划里记录结果与未覆盖项。
2. 核对暂存内容和源码包，没有配置、原始日志、截图或签名凭据。
3. 使用版本源 `android/app/build.gradle.kts` 生成版本，提交并创建对应 `app-v<version>` 标签。
4. 上传维护者 APK、该提交的源码归档、SHA-256 文件与产物核验报告；候选版标记为 prerelease。
5. 核对下载端的摘要与构建机一致，再交付测试。
6. 实体设备验收通过并关闭 P0/P1 问题后，才发布无候选后缀的版本。

CI 包、旧缓存包和其他签名的 APK 不能被重新命名成维护者发布包。
