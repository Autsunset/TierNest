package com.tiernest.app.engine

import com.tiernest.app.diagnostics.RootCommandPhase
import com.tiernest.app.diagnostics.RootCommandTiming
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import org.junit.Assert.*
import org.junit.Test
import java.io.IOException
import java.io.StringWriter
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class RootCommandTransportTest {
    private data class Record(val error: Throwable?, val code: Int?, val timing: RootCommandTiming)

    private class Fixture(timeout: Long = 2000) {
        val lines = Channel<String>(16)
        val records = mutableListOf<Record>()
        var flush: (String) -> Unit = {}
        var report: (Record) -> Unit = {}
        val writer = object : StringWriter() {
            override fun flush() { val command = toString(); buffer.setLength(0); flush(command.substringBefore(' ')) }
        }
        val transport = RootCommandTransport(writer, { lines.receiveCatching().getOrThrow() }, { true },
            { System.nanoTime() / 1_000_000 }, { _, error, code, timing ->
                Record(error, code, timing).let { records.add(it); report(it) }
            }, timeout)
    }

    @Test fun writeAndParseRunOffTheCallerAndHealthySamplingDoesNotLog() = runBlocking {
        val caller = Thread.currentThread()
        val f = Fixture()
        f.flush = { token ->
            assertNotSame(caller, Thread.currentThread())
            f.lines.trySend("alive=1")
            f.lines.trySend("__TN_DONE_$token:0")
        }
        assertEquals("alive=1", f.transport.call("status"))
        assertTrue(f.records.isEmpty())
        f.transport.call("start")
        val trace = f.records.single().timing
        assertEquals(RootCommandPhase.REPLY_COMPLETE, trace.phase)
        assertNotNull(trace.writeMs)
        assertNotNull(trace.firstLineMs)
    }

    @Test fun noReplyTimesOutWithoutCancellingController() = runBlocking {
        val f = Fixture(40)
        val error = runCatching { f.transport.call("status") }.exceptionOrNull()
        assertTrue(error is RootCommandTimeoutException)
        assertTrue(isActive)
        val record = f.records.single()
        // Coroutine debug stack recovery may copy an exception across dispatchers.
        assertTrue(generateSequence(error) { it.cause }.take(8).any { it === record.error })
        assertEquals(RootCommandPhase.WAITING_REPLY, record.timing.phase)
        assertNotNull(record.timing.writeMs)
        assertNull(record.timing.firstLineMs)
    }

    @Test fun partialReplyIsDistinguishableFromNoReply() = runBlocking {
        val f = Fixture(40)
        f.flush = { f.lines.trySend("alive=1") }
        assertTrue(runCatching { f.transport.call("sync") }.exceptionOrNull() is RootCommandTimeoutException)
        assertEquals(RootCommandPhase.READING_REPLY, f.records.single().timing.phase)
        assertNotNull(f.records.single().timing.firstLineMs)
    }

    @Test fun brokenWriteKeepsOriginalExceptionAndDoesNotClaimReplyArrived() = runBlocking {
        val f = Fixture()
        val failure = IOException("synthetic private payload")
        f.flush = { throw failure }
        val propagated = runCatching { f.transport.call("status") }.exceptionOrNull()
        assertTrue(generateSequence(propagated) { it.cause }.take(8).any { it === failure })
        assertEquals(RootCommandPhase.WRITING, f.records.single().timing.phase)
        assertNull(f.records.single().timing.writeMs)
        assertNull(f.records.single().timing.firstLineMs)
    }

    @Test fun fullyConsumedOperationFailureCanBeFollowedByAnotherCommand() = runBlocking {
        val f = Fixture()
        f.flush = { f.lines.trySend("__TN_DONE_$it:1") }
        assertTrue(runCatching { f.transport.call("probe") }.exceptionOrNull() is RootOperationException)
        assertEquals(RootCommandPhase.REPLY_COMPLETE, f.records.last().timing.phase)
        f.flush = { f.lines.trySend("alive=1"); f.lines.trySend("__TN_DONE_$it:0") }
        assertEquals("alive=1", f.transport.call("status"))
    }

    @Test fun malformedCompletionIsNotReportedAsSuccessful() = runBlocking {
        val f = Fixture()
        f.flush = { f.lines.trySend("__TN_DONE_$it:invalid") }
        assertNotNull(runCatching { f.transport.call("sync") }.exceptionOrNull())
        assertEquals(RootCommandPhase.READING_REPLY, f.records.single().timing.phase)
        assertNull(f.records.single().code)
    }

    @Test fun parentCancellationDoesNotBecomeAnAutomaticRecoveryError() = runBlocking {
        val f = Fixture(10_000)
        val written = CompletableDeferred<Unit>()
        f.flush = { written.complete(Unit) }
        val work = async { f.transport.call("status") }
        written.await()
        work.cancelAndJoin()
        assertTrue(f.records.isEmpty())
    }

    @Test fun deadlineAndFailureReportCanRunWhileCallerDispatcherIsBlocked() = runBlocking {
        val caller = Executors.newSingleThreadExecutor().asCoroutineDispatcher()
        try {
            withContext(caller) {
                val f = Fixture(100)
                val written = CompletableDeferred<Unit>()
                val reported = CountDownLatch(1)
                f.flush = { written.complete(Unit) }
                f.report = { if (it.error is RootCommandTimeoutException) reported.countDown() }
                val work = async { runCatching { f.transport.call("status") }.exceptionOrNull() }
                written.await()
                // Intentionally block the sole caller thread. Only IO may
                // deliver the deadline/report until this assertion releases it.
                assertTrue(reported.await(3, TimeUnit.SECONDS))
                assertTrue(work.await() is RootCommandTimeoutException)
                assertTrue(isActive)
            }
        } finally { caller.close() }
    }
}
