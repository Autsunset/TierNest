package com.tiernest.app.engine

import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test
import java.io.IOException
import java.io.Reader
import java.io.StringReader
import java.util.concurrent.atomic.AtomicReference

class RootOutputPumpTest {
    @Test fun commandDeadlineIsAnErrorWithoutCancellingItsController() = runBlocking {
        val error = runCatching { withRootDeadline(20) { delay(200); "late" } }.exceptionOrNull()
        assertTrue(error is RootCommandTimeoutException)
        assertTrue(isActive)
        assertEquals("next command", withRootDeadline(200) { "next command" })
    }

    @Test fun parentCancellationIsNotConvertedIntoAConnectionError() = runBlocking {
        val pending = async { withRootDeadline(10_000) { awaitCancellation() } }
        yield(); pending.cancel()
        val error = runCatching { pending.await() }.exceptionOrNull()
        assertTrue(error is CancellationException)
        assertFalse(error is RootCommandTimeoutException)
    }

    @Test fun pipeReadFailureIsDeliveredToCallerWithoutAnUncaughtCrash() = runBlocking {
        val uncaught = AtomicReference<Throwable?>()
        val reported = AtomicReference<Exception?>()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO + CoroutineExceptionHandler { _, error -> uncaught.set(error) })
        try {
            val expected = IOException("synthetic broken pipe")
            val reader = object : Reader() {
                override fun read(buffer: CharArray, off: Int, len: Int): Int = throw expected
                override fun close() = Unit
            }
            val pump = RootOutputPump(reader, scope, { reported.set(it) })
            val result = withTimeout(2000) { pump.lines.receiveCatching() }
            assertSame(expected, result.exceptionOrNull())
            assertSame(expected, reported.get())
            assertNull(uncaught.get())
            assertTrue(scope.isActive)
        } finally { scope.cancel() }
    }

    @Test fun eofPreservesFramingAndFinalPartialLine() = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        try {
            val pump = RootOutputPump(StringReader("ready\r\n\nlast"), scope, { throw AssertionError(it) })
            val all = withTimeout(2000) { buildList { for (line in pump.lines) add(line) } }
            assertEquals(listOf("ready", "", "last"), all)
        } finally { scope.cancel() }
    }

    @Test fun oversizedOutputFailsWithoutReadingAnUnboundedLine() = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        try {
            val pump = RootOutputPump(StringReader("x".repeat(100_000)), scope, {}, maxLineChars = 64)
            val result = withTimeout(2000) { pump.lines.receiveCatching() }
            assertTrue(result.exceptionOrNull() is IOException)
        } finally { scope.cancel() }
    }

    @Test fun cancellingFullBufferDoesNotReportAReadFailure() = runBlocking {
        val reported = AtomicReference<Exception?>()
        val job = SupervisorJob()
        val scope = CoroutineScope(job + Dispatchers.IO)
        val pump = RootOutputPump(StringReader("line\n".repeat(1000)), scope, { reported.set(it) })
        assertEquals("line", withTimeout(2000) { pump.lines.receive() })
        job.cancelAndJoin()
        assertNull(reported.get())
    }
}
