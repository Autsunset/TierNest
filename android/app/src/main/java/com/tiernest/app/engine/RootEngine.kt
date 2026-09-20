package com.tiernest.app.engine

import android.content.Context
import com.tiernest.app.data.ConfigCodec
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeUnit
import com.tiernest.app.diagnostics.AppDiagnostics
import com.tiernest.app.diagnostics.LogEvent

data class EngineStatus(val alive: Boolean = false, val cidr: String = "", val rx: Long = 0,
                        val tx: Long = 0, val table: String = "", val priority: String = "")

/** The reply frame was fully consumed; the Root session is still usable. */
internal class RootOperationException(message: String) : IllegalStateException(message)

/** Only a fixed action crosses the su pipe. Configuration is never interpolated. */
class RootEngine(private val context: Context, private val diagnostics: AppDiagnostics) {
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

    private suspend fun <T> command(retain: Boolean = false, preserveOnOperationFailure: Boolean = false,
                                    block: suspend (RootSession) -> T): T = mutex.withLock {
        withContext(Dispatchers.IO) {
            val ephemeral = session == null
            var success = false
            try {
                if (session == null) {
                    prepare()
                    session = try { RootSession(stage, diagnostics) } catch (error: java.io.IOException) {
                        throw IllegalStateException("无法调用 su。请在 Magisk、KernelSU 或 APatch 中为 TierNest 授予 Root；仅 ADB 有 Root 权限的设备不能直接连接。", error)
                    }
                    session!!.awaitReady()
                }
                block(session!!).also { success = true }
            } catch (error: RootOperationException) {
                // A completed read-only check must not tear down a live core.
                // I/O, framing errors and cancellation still close the session.
                success = preserveOnOperationFailure
                throw error
            } finally {
                if (!success || (ephemeral && !retain)) closeLocked()
            }
        }
    }

    private suspend fun closeLocked() = withContext(NonCancellable + Dispatchers.IO) {
        try { session?.close() } finally { session = null; connectionOwner = null }
    }

    private suspend fun callLocked(current: RootSession, action: String): String {
        try { return current.call(action) }
        catch (error: Exception) {
            // A timed-out/partial reply cannot be reused by the next command.
            if (error !is RootOperationException) {
                try { closeLocked() } catch (cleanup: Exception) { error.addSuppressed(cleanup) }
            }
            throw error
        }
    }

    suspend fun start(config: String, owner: String) = command(retain = true) {
        if (connectionOwner != null && connectionOwner != owner) it.call("stop")
        connectionOwner = owner
        File(stage, "effective.toml").writeText(ConfigCodec.effective(config,
            defaultHostname = com.tiernest.app.data.DeviceName.current(context)))
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
        val fields = callLocked(current, "status").lineSequence().filter { '=' in it }
            .associate { it.substringBefore('=') to it.substringAfter('=') }
        EngineStatus(fields["alive"] == "1", fields["cidr"].orEmpty(), fields["rx"]?.toLongOrNull() ?: 0,
            fields["tx"]?.toLongOrNull() ?: 0, fields["table"].orEmpty(), fields["pref"].orEmpty())
    }

    suspend fun peers(): String = mutex.withLock { session?.let { callLocked(it, "peers") } ?: "[]" }

    suspend fun sync(routes: List<String>) = mutex.withLock {
        val current = session ?: error("核心未连接")
        withContext(Dispatchers.IO) { File(stage, "routes.txt").writeText(routes.joinToString("\n", postfix = "\n")) }
        callLocked(current, "sync")
    }

    suspend fun validate(config: String) = command {
        File(stage, "effective.toml").writeText(ConfigCodec.effective(config,
            defaultHostname = com.tiernest.app.data.DeviceName.current(context)))
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

    private fun validateWifi(iface: String, gateway: String) {
        require(iface.matches(Regex("wlan[0-9]+"))) { "当前 Wi-Fi 接口不受支持" }
        require(!gateway.contains('/') && com.tiernest.app.data.RoutePlanner.cidr(gateway)?.prefix == 32)
    }

    private suspend fun readGateway(current: RootSession, iface: String, gateway: String): String {
        File(stage, "wifi-query").writeText("$iface $gateway\n")
        return current.call("gateway").trim().also { mac ->
            if (!mac.matches(Regex("([0-9a-f]{2}:){5}[0-9a-f]{2}")) || mac == "00:00:00:00:00:00" ||
                (mac.substringBefore(':').toInt(16) and 1) != 0) throw RootOperationException("无法读取 Wi-Fi 网关身份")
        }
    }

    suspend fun gatewayMac(iface: String, gateway: String): String {
        validateWifi(iface, gateway)
        return command(preserveOnOperationFailure = true) { readGateway(it, iface, gateway) }
    }

    suspend fun probeWifi(iface: String, gateway: String, source: String, target: String, port: Int, mac: String): Boolean {
        validateWifi(iface, gateway)
        listOf(source, target).forEach {
            require(!it.contains('/') && com.tiernest.app.data.RoutePlanner.cidr(it)?.prefix == 32)
        }
        require(port in 1..65535)
        return command(preserveOnOperationFailure = true) {
            if (readGateway(it, iface, gateway) != mac) throw RootOperationException("Wi-Fi 网关已变化，请重试")
            File(stage, "probe-query").writeText("$iface $source $target $port\n")
            val reply = it.call("probe")
            if (readGateway(it, iface, gateway) != mac) throw RootOperationException("Wi-Fi 网关已变化，请重试")
            when (reply) {
                "reachable=1" -> true
                "reachable=0" -> false
                else -> throw RootOperationException("家庭网络探测响应无效")
            }
        }
    }
}

private class RootSession(stage: File, private val diagnostics: AppDiagnostics) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val process = ProcessBuilder("su", "-c", "exec /system/bin/sh ${quote(File(stage, "engine.sh").path)} ${quote(stage.path)}")
        .redirectErrorStream(true).start()
    private val input = process.outputStream.bufferedWriter()
    private val output = RootOutputPump(process.inputStream.reader(), scope, {
        diagnostics.event(LogEvent.ROOT_OUTPUT_FAILED, it)
    })

    init {
        diagnostics.event(LogEvent.ROOT_SESSION_OPEN)
    }

    private suspend fun readLine(): String? {
        val next = output.lines.receiveCatching()
        next.exceptionOrNull()?.let {
            if (it is CancellationException) throw it
            throw java.io.IOException("Root output pipe failed", it)
        }
        return next.getOrNull()
    }

    suspend fun awaitReady() = withRootDeadline(30_000) {
        val message = StringBuilder()
        while (true) {
            val line = readLine() ?: error("Root 启动失败：${message.take(600)}")
            if (line == "__TN_READY__") break
            if (message.length < 600) message.appendLine(line)
        }
    }

    suspend fun call(action: String): String {
        require(action in setOf("start", "stop", "status", "sync", "peers", "backup", "import", "validate", "gateway", "probe"))
        val started = System.nanoTime()
        return try {
            withRootDeadline(25_000) {
                val token = UUID.randomUUID().toString().replace("-", "")
                withContext(Dispatchers.IO) { input.write("$token $action\n"); input.flush() }
                val result = StringBuilder()
                while (true) {
                    val line = readLine() ?: error("Root 会话已退出；连接已终止")
                    if (line.startsWith("__TN_DONE_$token:")) {
                        val code = line.substringAfter(':').toIntOrNull() ?: error("Root 响应格式无效")
                        if (action !in setOf("status", "peers", "sync") || code != 0) diagnostics.event(
                            LogEvent.ROOT_COMMAND_DONE, action = action, elapsedMs = (System.nanoTime() - started) / 1_000_000, code = code)
                        if (code != 0) throw RootOperationException("Root 操作失败 ($action)：${result.toString().trim().take(600)}")
                        break
                    }
                    check(result.length < 2 * 1024 * 1024) { "核心响应过大" }
                    result.appendLine(line)
                }
                result.toString().trim()
            }
        } catch (error: Exception) {
            if (error !is CancellationException) diagnostics.event(LogEvent.ROOT_COMMAND_FAILED, error,
                action = action, elapsedMs = (System.nanoTime() - started) / 1_000_000)
            throw error
        }
    }

    suspend fun close() = withContext(Dispatchers.IO) {
        try {
            runCatching { input.close() } // EOF triggers root cleanup, including on process death.
            if (!process.waitFor(15, TimeUnit.SECONDS)) {
                process.destroy()
                if (!process.waitFor(3, TimeUnit.SECONDS)) {
                    process.destroyForcibly()
                    process.waitFor(2, TimeUnit.SECONDS)
                }
            }
        } finally {
            scope.cancel()
            diagnostics.event(LogEvent.ROOT_SESSION_CLOSE)
        }
    }

    companion object { fun quote(value: String) = "'" + value.replace("'", "'\\''") + "'" }
}
