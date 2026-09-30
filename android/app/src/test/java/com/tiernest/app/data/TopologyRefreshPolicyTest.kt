package com.tiernest.app.data

import org.junit.Assert.*
import org.junit.Test

class TopologyRefreshPolicyTest {
    @Test fun overviewKeepsCounterTicksWhileReducingPeerQueries() {
        val policy = TopologyRefreshPolicy()
        var queries = 0
        for (now in 0L until 60_000L step 3000) {
            if (policy.needed(now)) { queries++; policy.refreshed(now) }
        }
        assertEquals(4, queries) // Twenty counter ticks, four peer queries.
        assertTrue(policy.needed(60_000))
    }

    @Test fun nodePageEventsAndMaintenanceAlwaysRefresh() {
        val policy = TopologyRefreshPolicy()
        policy.refreshed(0)
        assertFalse(policy.needed(3000))
        assertTrue(policy.needed(3000, force = true))
        policy.refreshed(3000)
        assertTrue(policy.needed(3001, force = true))
        assertFalse(policy.needed(3001))
    }

    @Test fun newBackendNeverReusesAnOldTopology() {
        val policy = TopologyRefreshPolicy()
        policy.refreshed(1000)
        assertFalse(policy.needed(1001))
        policy.reset()
        assertTrue(policy.needed(1001))
    }
}
