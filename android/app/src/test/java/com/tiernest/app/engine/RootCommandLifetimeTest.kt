package com.tiernest.app.engine

import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test
import java.io.IOException

class RootCommandLifetimeTest {
    @Test fun completedReadOnlyFailureKeepsExistingCoreUsable() = runBlocking {
        var closed = false
        val rejected = RootOperationException("invalid draft or failed backup")
        val error = runCatching {
            withRootCommandLifetime(false, false, true, { closed = true }) { throw rejected }
        }.exceptionOrNull()
        assertSame(rejected, error)
        assertFalse(closed)
        assertEquals("alive", withRootCommandLifetime(false, false, true, { closed = true }) { "alive" })
        assertFalse(closed)
    }

    @Test fun temporaryReadOnlySessionsCloseOnSuccessAndFailure() = runBlocking {
        var closes = 0
        withRootCommandLifetime(true, false, true, { closes++ }) { "validated" }
        runCatching { withRootCommandLifetime(true, false, true, { closes++ }) { throw RootOperationException("rejected") } }
        assertEquals(2, closes)
    }

    @Test fun mutationFailureTimeoutAndCancellationCloseEvenAnExistingSession() = runBlocking {
        var closes = 0
        runCatching { withRootCommandLifetime(false, true, false, { closes++ }) { throw RootOperationException("start failed") } }
        val timeout = runCatching { withRootCommandLifetime(false, false, true, { closes++ }) { throw RootCommandTimeoutException() } }.exceptionOrNull()
        assertTrue(timeout is RootCommandTimeoutException)
        val cancelled = runCatching { withRootCommandLifetime(false, false, true, { closes++ }) { throw CancellationException() } }.exceptionOrNull()
        assertTrue(cancelled is CancellationException)
        assertEquals(3, closes)
        assertTrue(isActive)
    }

    @Test fun failedCleanupKeepsThePrimaryErrorAndItsEvidence() = runBlocking {
        val primary = RootCommandTimeoutException()
        val cleanup = IOException("cleanup failed")
        val error = runCatching { withRootCommandLifetime(false, false, true, { throw cleanup }) { throw primary } }.exceptionOrNull()
        assertSame(primary, error)
        assertSame(cleanup, error!!.suppressed.single())
    }
}
