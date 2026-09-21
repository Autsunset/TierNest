package com.tiernest.app.data

import org.junit.Assert.*
import org.junit.Test

class MinimalRoutesTest {
    @Test fun peerChurnInsideAnExistingSubnetKeepsTheVpnRouteSignature() {
        val before = listOf("10.77.0.0/24", "198.51.100.9/32")
        val joined = before + listOf("10.77.0.2/32", "10.77.0.9/32", "10.77.0.0/24")
        assertEquals(RoutePlanner.minimalRoutes(before), RoutePlanner.minimalRoutes(joined))
    }

    @Test fun independentHostsAndSubnetsAreNotExpandedOrDropped() {
        val routes = listOf("10.77.0.2/32", "10.77.0.3/32", "198.51.100.0/25", "198.51.100.128/25")
        assertEquals(routes.sorted(), RoutePlanner.minimalRoutes(routes.reversed()))
    }

    @Test fun physicalConflictExclusionStillHappensBeforeMinimizing() {
        val peer = Peer("fixture", "10.77.0.9", 1, null, "DIRECT", emptyList())
        val plan = RoutePlanner.plan("10.77.0.2/24", listOf(peer), listOf("10.77.0.128/25"))
        assertEquals(listOf("10.77.0.9/32"), RoutePlanner.minimalRoutes(plan.routes))
        assertTrue(plan.excluded.contains("10.77.0.2/24"))
    }
}
