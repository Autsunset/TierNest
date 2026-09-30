package com.tiernest.app.data

import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.collectLatest
import org.junit.Assert.*
import org.junit.Test

class UiSamplingTest {
    @Test fun screenOffAndCoreStandbyCancelTheTimerWithoutNeedingAnActivityStop() = runBlocking {
        val visible = MutableStateFlow(true)
        val data = MutableStateFlow(true)
        val peers = MutableStateFlow(false)
        val screen = MutableStateFlow(true)
        val core = MutableStateFlow(true)
        val starts = Channel<UiSamplingRequest>(Channel.UNLIMITED)
        val stops = Channel<Unit>(Channel.UNLIMITED)
        val sampler = launch {
            uiSamplingRequests(visible, data, peers, screen, core).collectLatest { request ->
                if (request.active) {
                    starts.send(request)
                    try { awaitCancellation() } finally { stops.trySend(Unit) }
                }
            }
        }
        try {
            withTimeout(3000) { starts.receive() }
            screen.value = false // Activity deliberately remains started/visible.
            withTimeout(3000) { stops.receive() }
            assertTrue(visible.value)
            assertTrue(starts.tryReceive().isFailure)
            screen.value = true
            withTimeout(3000) { starts.receive() }
            core.value = false // Automatic standby with the UI still visible.
            withTimeout(3000) { stops.receive() }
            peers.value = true
            yield()
            assertTrue(starts.tryReceive().isFailure)
            core.value = true
            assertTrue(withTimeout(3000) { starts.receive() }.refreshPeers)
        } finally { sampler.cancelAndJoin() }
    }

    @Test fun leavingTheDataPagesStopsSamplingAndNodeEntryRefreshesImmediately() = runBlocking {
        val visible = MutableStateFlow(true)
        val data = MutableStateFlow(true)
        val peers = MutableStateFlow(false)
        val screen = MutableStateFlow(true)
        val core = MutableStateFlow(true)
        val requests = Channel<UiSamplingRequest>(Channel.UNLIMITED)
        val collector = launch { uiSamplingRequests(visible, data, peers, screen, core).collect { requests.send(it) } }
        try {
            assertEquals(UiSamplingRequest(true, false), withTimeout(3000) { requests.receive() })
            peers.value = true
            assertEquals(UiSamplingRequest(true, true), withTimeout(3000) { requests.receive() })
            data.value = false
            assertFalse(withTimeout(3000) { requests.receive() }.active)
            visible.value = false
            yield()
            assertTrue(requests.tryReceive().isFailure) // Equivalent inactive state is deduplicated.
            data.value = true
            visible.value = true
            assertEquals(UiSamplingRequest(true, true), withTimeout(3000) { requests.receive() })
        } finally { collector.cancelAndJoin() }
    }
}
