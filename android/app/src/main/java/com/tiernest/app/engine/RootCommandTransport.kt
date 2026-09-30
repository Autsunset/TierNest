package com.tiernest.app.engine

import com.tiernest.app.diagnostics.RootCommandPhase
import com.tiernest.app.diagnostics.RootCommandTiming
import com.tiernest.app.diagnostics.RootCommandStage
import com.tiernest.app.diagnostics.RootFailureKind
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import java.io.IOException
import java.io.Writer
import java.util.UUID

/** One caller at a time (RootEngine's mutex). A failed/partial exchange requires
 * closing the session; a fully consumed operation error leaves it usable.
 * IO owns the deadline and reply parsing, independent of Main's message queue.
 * Blocking writes and whole-process suspension can still delay cancellation. */
internal class RootCommandTransport(
    private val input: Writer,
    private val readLine: suspend () -> String?,
    private val processAlive: () -> Boolean,
    private val realtimeMillis: () -> Long,
    private val report: (String, Throwable?, Int?, RootCommandTiming) -> Unit,
    private val timeoutMs: Long = 25_000,
) {
    suspend fun awaitReady() = withContext(Dispatchers.IO) {
        withRootDeadline(30_000) {
            val message = StringBuilder()
            while (true) {
                val line = readLine() ?: error("Root 启动失败：${message.take(600)}")
                if (line == "__TN_READY__") break
                if (message.length < 600) message.appendLine(line)
            }
        }
    }

    suspend fun call(action: String): String {
        require(action in setOf("start", "stop", "status", "sync", "peers", "backup", "import", "validate", "gateway", "probe", "hotspot"))
        val started = System.nanoTime()
        val realtimeStarted = realtimeMillis()
        fun elapsed() = (System.nanoTime() - started) / 1_000_000
        var phase = RootCommandPhase.QUEUED
        var writeMs: Long? = null
        var firstLineMs: Long? = null
        var stage: RootCommandStage? = null
        var stageMs: Long? = null
        var completed: Pair<Int, String>? = null
        fun timing(failure: RootFailureKind? = null) = RootCommandTiming(phase, elapsed(), realtimeMillis() - realtimeStarted,
            writeMs, firstLineMs, processAlive(), stage, stageMs, failure)
        return withContext(Dispatchers.IO) {
            try {
                try { withRootDeadline(timeoutMs) {
                    val token = UUID.randomUUID().toString().replace("-", "")
                    phase = RootCommandPhase.WRITING
                    input.write("$token $action\n")
                    input.flush()
                    writeMs = elapsed()
                    phase = RootCommandPhase.WAITING_REPLY
                    val result = StringBuilder()
                    while (true) {
                        val line = readLine() ?: error("Root 会话已退出；连接已终止")
                        if (firstLineMs == null) firstLineMs = elapsed()
                        phase = RootCommandPhase.READING_REPLY
                        if (line.startsWith("__TN_STAGE_$token:")) {
                            stage = RootCommandStage.entries.firstOrNull { it.name == line.substringAfter(':') }
                                ?: error("Root 阶段响应格式无效")
                            stageMs = elapsed()
                            continue
                        }
                        if (line.startsWith("__TN_DONE_$token:")) {
                            val code = line.substringAfter(':').toIntOrNull() ?: error("Root 响应格式无效")
                            phase = RootCommandPhase.REPLY_COMPLETE
                            completed = code to result.toString().trim()
                            break
                        }
                        check(result.length + line.length < 2 * 1024 * 1024) { "核心响应过大" }
                        result.appendLine(line)
                    }
                    Unit
                } } catch (timeout: RootCommandTimeoutException) {
                    // Cancellation can win just after the entire reply is consumed.
                    // Accept that framed outcome, never wait beyond the deadline for
                    // missing bytes. A parent's stop/cancellation must still win.
                    if (completed == null) throw timeout
                }
                currentCoroutineContext().ensureActive()
                val (code, result) = checkNotNull(completed)
                if (code != 0) throw RootOperationException("Root 操作失败 ($action)：${result.take(600)}")
                if (action !in setOf("status", "peers", "sync")) report(action, null, code, timing())
                result
            } catch (error: Exception) {
                if (error !is CancellationException) {
                    val kind = when (error) {
                        is RootCommandTimeoutException -> RootFailureKind.TIMEOUT
                        is RootOperationException -> RootFailureKind.OPERATION
                        is IOException -> RootFailureKind.TRANSPORT
                        else -> RootFailureKind.PROTOCOL
                    }
                    report(action, error, completed?.first, timing(kind))
                }
                throw error
            }
        }
    }
}
