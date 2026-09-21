package com.tiernest.app.diagnostics

import java.io.File
import java.io.FileOutputStream
import java.time.Instant
import java.util.Collections
import java.util.IdentityHashMap

enum class LogEvent {
    APP_START, UI_ENTER, UI_LEAVE, SERVICE_CREATE, SERVICE_DESTROY, SERVICE_START,
    CONNECT_REQUEST, STOP_REQUEST, CORE_START, CORE_READY, CORE_STOP, CONNECTION_FAILED,
    HOME_STANDBY, SCREEN_STANDBY, NETWORK_CHANGED, VPN_REVOKED, ORPHANED_REQUEST,
    ROOT_SESSION_OPEN, ROOT_SESSION_CLOSE, ROOT_COMMAND_DONE, ROOT_COMMAND_FAILED,
    ROOT_OUTPUT_FAILED, ROOT_RECOVERY, HOTSPOT_STATE_CHANGED, OPERATION_FAILED, SETTINGS_FAILED, EVENT_SOURCE_FAILED,
    EXPORT, LOGGING_ENABLED, FATAL
}

enum class RootCommandPhase { QUEUED, WRITING, WAITING_REPLY, READING_REPLY, REPLY_COMPLETE }

/** Fixed fields only; never carries a command payload or response text. */
data class RootCommandTiming(val phase: RootCommandPhase, val awakeMs: Long, val realtimeMs: Long,
                             val writeMs: Long?, val firstLineMs: Long?, val processAlive: Boolean)

/** No Throwable.message/toString, configuration, addresses or pipe contents.
 * Stack frames are enough to locate the failing code without echoing input. */
object DiagnosticRecords {
    private val actions = setOf("start", "stop", "status", "sync", "peers", "backup", "import", "validate", "gateway", "probe", "hotspot")
    private val symbol = Regex("[A-Za-z0-9_.$<>-]{1,240}")
    private fun symbol(value: String) = value.takeIf { symbol.matches(it) } ?: "[symbol]"

    fun entry(event: LogEvent, error: Throwable? = null, action: String? = null,
              mode: String? = null, elapsedMs: Long? = null, code: Int? = null,
              at: Long = System.currentTimeMillis(), versionCode: Int? = null,
              root: RootCommandTiming? = null, recovery: com.tiernest.app.data.RecoveryDecision? = null): String = buildString {
        append(Instant.ofEpochMilli(at)).append(' ').append(event.name)
        if (versionCode != null) append(" version_code=").append(versionCode)
        if (action != null) append(" action=").append(action.takeIf { it in actions } ?: "unknown")
        if (mode != null) append(" mode=").append(mode.takeIf { it == "ROOT" || it == "VPN" } ?: "unknown")
        if (elapsedMs != null) append(" elapsed_ms=").append(elapsedMs.coerceAtLeast(0))
        if (code != null) append(" code=").append(code)
        if (recovery != null) append(" decision=").append(recovery.name)
        root?.let {
            append(" phase=").append(it.phase.name)
            append(" awake_ms=").append(it.awakeMs.coerceAtLeast(0))
            append(" realtime_ms=").append(it.realtimeMs.coerceAtLeast(0))
            it.writeMs?.let { ms -> append(" write_ms=").append(ms.coerceAtLeast(0)) }
            it.firstLineMs?.let { ms -> append(" first_line_ms=").append(ms.coerceAtLeast(0)) }
            append(" process_alive=").append(it.processAlive)
        }
        append('\n')
        if (error != null) {
            val seen = Collections.newSetFromMap(IdentityHashMap<Throwable, Boolean>())
            fun appendError(value: Throwable, depth: Int, label: String) {
                if (depth >= 6 || seen.size >= 8 || length >= 24 * 1024 || !seen.add(value)) return
                append(label).append(symbol(value.javaClass.name)).append(" [message omitted]\n")
                value.stackTrace.take(40).forEach { frame ->
                    if (length >= 24 * 1024) return@forEach
                    val file = frame.fileName?.substringAfterLast('/')?.substringAfterLast('\\')
                    append("  at ").append(symbol(frame.className)).append('.').append(symbol(frame.methodName))
                        .append('(').append(file?.let(::symbol) ?: "Unknown Source").append(':')
                        .append(frame.lineNumber).append(")\n")
                }
                value.suppressed.take(2).forEach { appendError(it, depth + 1, "Suppressed: ") }
                value.cause?.let { appendError(it, depth + 1, "Caused by: ") }
            }
            appendError(error, 0, "Exception: ")
        }
    }.take(24 * 1024)
}

/** Three bounded event files plus one durable, separately retained fatal report. */
class DiagnosticFiles(private val directory: File, private val maxBytes: Int = 256 * 1024) {
    @Synchronized fun append(text: String) {
        check(directory.isDirectory || directory.mkdirs())
        val raw = text.take(24 * 1024).toByteArray(Charsets.UTF_8)
        val data = raw.copyOf(minOf(raw.size, maxBytes))
        val current = File(directory, "events.0.log")
        if (current.length() + data.size > maxBytes) {
            File(directory, "events.2.log").delete()
            for (i in 1 downTo 0) {
                val source = File(directory, "events.$i.log")
                if (source.exists()) check(source.renameTo(File(directory, "events.${i + 1}.log")))
            }
        }
        FileOutputStream(current, true).use { it.write(data) }
    }

    // Separate from the event lock: a crashing writer must not deadlock its own
    // fatal report. Atomic replacement keeps the previous report until complete.
    fun fatal(text: String) {
        check(directory.isDirectory || directory.mkdirs())
        val pending = File(directory, "last-crash.tmp")
        FileOutputStream(pending).use { stream ->
            stream.write(text.take(32 * 1024).toByteArray(Charsets.UTF_8))
            stream.fd.sync()
        }
        check(pending.renameTo(File(directory, "last-crash.txt")))
    }

    @Synchronized fun snapshot(): String = buildString {
        for (name in listOf("events.2.log", "events.1.log", "events.0.log", "last-crash.txt")) {
            val file = File(directory, name)
            if (file.isFile) {
                append("\n--- ").append(name).append(" ---\n")
                file.inputStream().use { input ->
                    val buffer = ByteArray(maxBytes + 32 * 1024)
                    var used = 0
                    while (used < buffer.size) {
                        val count = input.read(buffer, used, buffer.size - used)
                        if (count < 0) break
                        used += count
                    }
                    append(String(buffer, 0, used, Charsets.UTF_8))
                }
            }
        }
    }

    @Synchronized fun clear() {
        for (name in listOf("events.0.log", "events.1.log", "events.2.log", "last-crash.txt", "last-crash.tmp")) {
            val file = File(directory, name)
            check(!file.exists() || file.delete())
        }
    }
}

/** Always delegate to Android's crash handler; never continue a broken process. */
class RecordingCrashHandler(private val record: (Throwable) -> Unit,
                            private val next: Thread.UncaughtExceptionHandler) : Thread.UncaughtExceptionHandler {
    @Synchronized override fun uncaughtException(thread: Thread, error: Throwable) {
        try { record(error) } catch (_: Throwable) { /* Best effort, including OOM. */ }
        finally { next.uncaughtException(thread, error) }
    }
}
