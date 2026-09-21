package com.tiernest.app.diagnostics

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Process
import com.tiernest.app.BuildConfig
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File
import java.time.Instant
import java.util.concurrent.atomic.AtomicLong

class AppDiagnostics(private val context: Context) {
    private val settings = context.getSharedPreferences("diagnostics", Context.MODE_PRIVATE)
    private val enabledState = MutableStateFlow(runCatching { settings.getBoolean("enabled", true) }.getOrDefault(true))
    val enabled = enabledState.asStateFlow()
    private val storageErrorState = MutableStateFlow(false)
    val storageError = storageErrorState.asStateFlow()
    private val files = DiagnosticFiles(File(context.filesDir, "diagnostics"))
    private val dropped = AtomicLong()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val queue = Channel<Work>(128)
    private sealed interface Work {
        data class Append(val text: String) : Work
        data class Read(val reply: CompletableDeferred<String>) : Work
        data class Clear(val reply: CompletableDeferred<Unit>) : Work
    }

    init {
        scope.launch {
            for (work in queue) {
                try {
                    when (work) {
                        is Work.Append -> files.append(work.text)
                        is Work.Read -> work.reply.complete(files.snapshot())
                        is Work.Clear -> { files.clear(); work.reply.complete(Unit) }
                    }
                    storageErrorState.value = false
                } catch (error: Exception) {
                    storageErrorState.value = true
                    when (work) {
                        is Work.Read -> work.reply.completeExceptionally(error)
                        is Work.Clear -> work.reply.completeExceptionally(error)
                        else -> Unit
                    }
                }
            }
        }
    }

    fun installCrashHandler() {
        val previous = Thread.getDefaultUncaughtExceptionHandler() ?: Thread.UncaughtExceptionHandler { _, _ ->
            Process.killProcess(Process.myPid())
            kotlin.system.exitProcess(10)
        }
        Thread.setDefaultUncaughtExceptionHandler(RecordingCrashHandler({ error ->
            if (enabled.value) files.fatal("TierNest ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE}) pid=${Process.myPid()}\n" +
                DiagnosticRecords.entry(LogEvent.FATAL, error))
        }, previous))
    }

    fun event(event: LogEvent, error: Throwable? = null, action: String? = null,
              mode: String? = null, elapsedMs: Long? = null, code: Int? = null,
              root: RootCommandTiming? = null, recovery: com.tiernest.app.data.RecoveryDecision? = null) {
        if (!enabled.value) return
        // Logging failure must never become the next application crash.
        runCatching {
            if (!queue.trySend(Work.Append(DiagnosticRecords.entry(event, error, action, mode, elapsedMs, code,
                versionCode = BuildConfig.VERSION_CODE, root = root, recovery = recovery))).isSuccess) dropped.incrementAndGet()
        }.onFailure { dropped.incrementAndGet() }
    }

    suspend fun setEnabled(value: Boolean) = withContext(Dispatchers.IO) {
        check(settings.edit().putBoolean("enabled", value).commit()) { "无法保存日志设置" }
        enabledState.value = value
        if (value) event(LogEvent.LOGGING_ENABLED)
    }

    suspend fun clear() {
        val reply = CompletableDeferred<Unit>()
        check(withTimeoutOrNull(10_000) { queue.send(Work.Clear(reply)); reply.await(); true } == true) { "清空日志超时，请稍后重试" }
    }

    suspend fun report(): String = withContext(Dispatchers.IO) {
        event(LogEvent.EXPORT)
        val log = withTimeoutOrNull(10_000) {
            val reply = CompletableDeferred<String>()
            queue.send(Work.Read(reply)); reply.await()
        } ?: error("读取诊断日志超时，请稍后重试")
        buildString {
            appendLine("TierNest diagnostic report / format 1")
            appendLine("generated=${Instant.now()}")
            appendLine("app=${BuildConfig.VERSION_NAME} code=${BuildConfig.VERSION_CODE}")
            val apkHash = runCatching {
                val digest = java.security.MessageDigest.getInstance("SHA-256")
                File(context.applicationInfo.sourceDir).inputStream().use { input ->
                    val buffer = ByteArray(16 * 1024)
                    while (true) { val n = input.read(buffer); if (n < 0) break; digest.update(buffer, 0, n) }
                }
                digest.digest().joinToString("") { "%02x".format(it) }
            }.getOrDefault("unavailable")
            appendLine("apk_sha256=$apkHash")
            appendLine("android=${Build.VERSION.RELEASE} sdk=${Build.VERSION.SDK_INT}")
            appendLine("manufacturer=${Build.MANUFACTURER} model=${Build.MODEL}")
            appendLine("abi=${Build.SUPPORTED_ABIS.joinToString(",")}")
            val connection = context.getSharedPreferences("tiernest", Context.MODE_PRIVATE)
            val mode = connection.getString("connectionMode", "")?.takeIf { it == "ROOT" || it == "VPN" } ?: "unknown"
            appendLine("mode=$mode requested=${connection.getBoolean("requested", false)} automatic=${connection.getBoolean("automatic", false)} screen_suspend=${connection.getBoolean("screen", false)}")
            appendLine("hotspot_access=${connection.getBoolean("hotspotAccess", false)}")
            appendLine("pid=${Process.myPid()} recording=${enabled.value} dropped_events=${dropped.get()}")
            val vm = Runtime.getRuntime()
            appendLine("heap_used=${vm.totalMemory() - vm.freeMemory()} heap_max=${vm.maxMemory()}")
            appendLine("Exception messages, configuration, network identities and endpoints are intentionally omitted.")
            appendLine("\n--- system exit records (this application only) ---")
            if (Build.VERSION.SDK_INT >= 30) {
                val exits = runCatching {
                    context.getSystemService(ActivityManager::class.java).getHistoricalProcessExitReasons(context.packageName, 0, 8)
                        .filter { it.processName == context.packageName }
                }.getOrNull()
                if (exits == null) appendLine("unavailable")
                else exits.forEach { exit ->
                    appendLine("time=${Instant.ofEpochMilli(exit.timestamp)} pid=${exit.pid} reason=${exit.reason} status=${exit.status} importance=${exit.importance} pss_kb=${exit.pss} rss_kb=${exit.rss}")
                }
            } else appendLine("unavailable on Android below 11")
            append(log)
        }
    }
}
