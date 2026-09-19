package com.tiernest.app.engine

import android.content.Context
import com.tiernest.app.data.ConfigCodec
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeUnit

data class EngineStatus(val alive: Boolean = false, val cidr: String = "", val rx: Long = 0,
                        val tx: Long = 0, val table: String = "", val priority: String = "")

/** Only a fixed action crosses the su pipe. Configuration is never interpolated. */
class RootEngine(private val context: Context) {
    val stage = File(context.filesDir, "engine")
    private val mutex = Mutex()
    private var session: RootSession? = null
    private var connectionOwner: String? = null

    private fun prepare() {
        check(android.os.Build.SUPPORTED_ABIS.contains("arm64-v8a")) { "此版本的 Root 核心仅支持 arm64 Android 设备" }
        stage.mkdirs()
        val revision = "${com.tiernest.app.BuildConfig.VERSION_CODE}-${context.packageManager.getPackageInfo(context.packageName, 0).lastUpdateTime}"
        val stamp = File(stage, "revision")
        if (stamp.takeIf { it.isFile }?.readText() == revision) return
        context.assets.list("engine").orEmpty().forEach { name ->
            context.assets.open("engine/$name").use { input -> File(stage, name).outputStream().use(input::copyTo) }
        }
        stamp.writeText(revision)
    }

    private suspend fun <T> command(retain: Boolean = false, block: suspend (RootSession) -> T): T = mutex.withLock {
        withContext(Dispatchers.IO) {
            val ephemeral = session == null
            var success = false
            try {
                if (session == null) {
                    prepare()
                    session = try { RootSession(stage) } catch (error: java.io.IOException) {
                        throw IllegalStateException("无法调用 su。请在 Magisk、KernelSU 或 APatch 中为 TierNest 授予 Root；仅 ADB 有 Root 权限的设备不能直接连接。", error)
                    }
                    session!!.awaitReady()
                }
                block(session!!).also { success = true }
            } finally {
                if (!success || (ephemeral && !retain)) closeLocked()
            }
        }
    }

    private suspend fun closeLocked() = withContext(NonCancellable + Dispatchers.IO) {
        session?.close()
        session = null
        connectionOwner = null
    }

    suspend fun start(config: String, owner: String) = command(retain = true) {
        if (connectionOwner != null && connectionOwner != owner) it.call("stop")
        connectionOwner = owner
        File(stage, "effective.toml").writeText(ConfigCodec.effective(config))
        it.call("start")
    }

    suspend fun stop(owner: String? = null) = mutex.withLock {
        if (owner != null && connectionOwner != owner) return@withLock
        withContext(Dispatchers.IO) {
            try { session?.call("stop") } finally { closeLocked() }
        }
    }

    suspend fun status(): EngineStatus = mutex.withLock {
        val current = session ?: return@withLock EngineStatus()
        val fields = current.call("status").lineSequence().filter { '=' in it }
            .associate { it.substringBefore('=') to it.substringAfter('=') }
        EngineStatus(fields["alive"] == "1", fields["cidr"].orEmpty(), fields["rx"]?.toLongOrNull() ?: 0,
            fields["tx"]?.toLongOrNull() ?: 0, fields["table"].orEmpty(), fields["pref"].orEmpty())
    }

    suspend fun peers(): String = mutex.withLock { session?.call("peers") ?: "[]" }

    suspend fun sync(routes: List<String>) = mutex.withLock {
        val current = session ?: error("核心未连接")
        withContext(Dispatchers.IO) { File(stage, "routes.txt").writeText(routes.joinToString("\n", postfix = "\n")) }
        current.call("sync")
    }

    suspend fun validate(config: String) = command {
        File(stage, "effective.toml").writeText(ConfigCodec.effective(config))
        it.call("validate")
    }

    suspend fun backup(config: String): String = command {
        File(stage, "backup.toml").writeText(config)
        try { it.call("backup").trim() } finally { File(stage, "backup.toml").delete() }
    }

    suspend fun importModule(): String = command {
        File(stage, "import").deleteRecursively()
        it.call("import").trim()
    }

    suspend fun gatewayMac(iface: String, gateway: String): String = command {
        require(iface.matches(Regex("wlan[0-9]+"))) { "当前 Wi-Fi 接口不受支持" }
        require(com.tiernest.app.data.RoutePlanner.cidr(gateway)?.prefix == 32)
        File(stage, "wifi-query").writeText("$iface $gateway\n")
        it.call("gateway").trim().also { mac ->
            require(mac.matches(Regex("([0-9a-f]{2}:){5}[0-9a-f]{2}"))) { "无法读取 Wi-Fi 网关身份" }
        }
    }
}

private class RootSession(stage: File) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val lines = Channel<String>(Channel.UNLIMITED)
    private val process = ProcessBuilder("su", "-c", "exec /system/bin/sh ${quote(File(stage, "engine.sh").path)} ${quote(stage.path)}")
        .redirectErrorStream(true).start()
    private val input = process.outputStream.bufferedWriter()

    init {
        scope.launch {
            try {
                process.inputStream.bufferedReader().use { reader ->
                    while (true) lines.send(reader.readLine() ?: break)
                }
            } finally { lines.close() }
        }
    }

    suspend fun awaitReady() = withTimeout(30_000) {
        val message = StringBuilder()
        while (true) {
            val line = lines.receiveCatching().getOrNull() ?: error("Root 启动失败：${message.take(600)}")
            if (line == "__TN_READY__") break
            if (message.length < 600) message.appendLine(line)
        }
    }

    suspend fun call(action: String): String = withTimeout(25_000) {
        require(action in setOf("start", "stop", "status", "sync", "peers", "backup", "import", "validate", "gateway"))
        val token = UUID.randomUUID().toString().replace("-", "")
        withContext(Dispatchers.IO) { input.write("$token $action\n"); input.flush() }
        val result = StringBuilder()
        while (true) {
            val line = lines.receiveCatching().getOrNull() ?: error("Root 会话已退出；连接已终止")
            if (line.startsWith("__TN_DONE_$token:")) {
                check(line.substringAfter(':') == "0") { "Root 操作失败 ($action)：${result.toString().trim().take(600)}" }
                break
            }
            check(result.length < 2 * 1024 * 1024) { "核心响应过大" }
            result.appendLine(line)
        }
        result.toString().trim()
    }

    suspend fun close() = withContext(Dispatchers.IO) {
        runCatching { input.close() } // EOF triggers root cleanup, including on process death.
        if (!process.waitFor(15, TimeUnit.SECONDS)) {
            process.destroy()
            process.waitFor(3, TimeUnit.SECONDS)
        }
        scope.cancel()
    }

    companion object { fun quote(value: String) = "'" + value.replace("'", "'\\''") + "'" }
}
