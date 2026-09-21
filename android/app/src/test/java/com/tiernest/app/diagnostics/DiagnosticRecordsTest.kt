package com.tiernest.app.diagnostics

import org.junit.Assert.*
import org.junit.Test
import java.nio.file.Files

class DiagnosticRecordsTest {
    @Test fun transportTraceUsesOnlyTypedPhasesNumbersAndBooleans() {
        val record = DiagnosticRecords.entry(LogEvent.ROOT_COMMAND_FAILED,
            IllegalStateException("do not export this payload"), action = "status",
            root = RootCommandTiming(RootCommandPhase.WAITING_REPLY, 25_000, 40_000, 2, null, true),
            recovery = com.tiernest.app.data.RecoveryDecision.RETRY)
        assertTrue(record.contains("decision=RETRY phase=WAITING_REPLY awake_ms=25000 realtime_ms=40000 write_ms=2 process_alive=true"))
        assertFalse(record.contains("first_line_ms="))
        assertFalse(record.contains("do not export this payload"))
    }

    @Test fun exceptionsKeepFramesButNeverEchoSecretsOrAddresses() {
        val sensitive = "secret-fixture tcp://peer.example.invalid:1234 192.0.2.99 network_name=private-name"
        val cause = IllegalArgumentException(sensitive)
        val error = IllegalStateException(sensitive, cause)
        error.addSuppressed(UnsupportedOperationException(sensitive))
        error.stackTrace = arrayOf(StackTraceElement("example.Worker", "refresh", "/private/folder/Worker.kt", 42))
        val report = DiagnosticRecords.entry(LogEvent.ROOT_OUTPUT_FAILED, error, action = sensitive, mode = sensitive)
        for (secret in listOf("secret-fixture", "peer.example.invalid", "192.0.2.99", "private-name", "/private/folder")) {
            assertFalse(report.contains(secret))
        }
        assertTrue(report.contains("example.Worker.refresh(Worker.kt:42)"))
        assertTrue(report.contains("Caused by: java.lang.IllegalArgumentException"))
        assertTrue(report.contains("Suppressed: java.lang.UnsupportedOperationException"))
        assertTrue(report.contains("action=unknown mode=unknown"))
    }

    @Test fun deepAndCyclicCausesStayBounded() {
        val first = Exception("omitted"); val second = Exception("omitted", first); first.initCause(second)
        val report = DiagnosticRecords.entry(LogEvent.FATAL, first)
        assertTrue(report.length < 24 * 1024)
        assertFalse(report.contains("omitted\n"))
    }

    @Test fun rotationKeepsRecentEventsAndFatalAcrossRestarts() {
        val dir = Files.createTempDirectory("diagnostics-test").toFile()
        try {
            val files = DiagnosticFiles(dir, 512)
            files.fatal("FATAL fixture-frame\n")
            repeat(150) { files.append("event-$it ".repeat(5) + "\n") }
            assertTrue(dir.listFiles()!!.filter { it.name.startsWith("events") }.all { it.length() <= 512 })
            val restored = DiagnosticFiles(dir, 512).snapshot()
            assertTrue(restored.contains("event-149"))
            assertFalse(restored.contains("event-0 "))
            assertTrue(restored.contains("FATAL fixture-frame"))
            val unrelated = java.io.File(dir, "unrelated.toml").apply { writeText("preserve") }
            files.clear()
            assertEquals("", files.snapshot())
            assertEquals("preserve", unrelated.readText())
        } finally { dir.deleteRecursively() }
    }

    @Test fun recordingFailureStillDelegatesTheOriginalCrash() {
        val original = IllegalStateException("fixture")
        var delegated: Throwable? = null
        val handler = RecordingCrashHandler({ throw java.io.IOException("disk unavailable") },
            Thread.UncaughtExceptionHandler { _, error -> delegated = error })
        handler.uncaughtException(Thread.currentThread(), original)
        assertSame(original, delegated)
    }

    @Test fun successfulFatalRecordIsWrittenBeforeDelegation() {
        var recorded = false
        val handler = RecordingCrashHandler({ recorded = true },
            Thread.UncaughtExceptionHandler { _, _ -> assertTrue(recorded) })
        handler.uncaughtException(Thread.currentThread(), IllegalStateException())
    }
}
