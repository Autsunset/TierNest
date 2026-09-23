package com.tiernest.app.data

import org.junit.Assert.*
import org.junit.Test

class RootMaintenancePolicyTest {
    private val routes = listOf("10.77.0.0/24", "198.51.100.9/32")

    @Test fun unchangedRoutesSkipSyncUntilTheForcedPass() {
        val policy = RootMaintenancePolicy(forceAfterMs = 1000)
        assertTrue(policy.routeSyncNeeded(routes, leaseHeld = false, now = 0))
        policy.routesSynced(routes, now = 0)
        assertFalse(policy.routeSyncNeeded(routes, leaseHeld = true, now = 500))
        assertTrue(policy.routeSyncNeeded(routes, leaseHeld = true, now = 1000))
    }

    @Test fun anyInputChangeResyncsImmediately() {
        val policy = RootMaintenancePolicy()
        policy.routesSynced(routes, now = 0)
        assertTrue("lease lost", policy.routeSyncNeeded(routes, leaseHeld = false, now = 1))
        assertTrue("peer joined", policy.routeSyncNeeded(routes + "10.77.0.9/32", leaseHeld = true, now = 1))
        assertTrue("peer left", policy.routeSyncNeeded(routes.take(1), leaseHeld = true, now = 1))
        policy.reset()
        assertTrue("after stop", policy.routeSyncNeeded(routes, leaseHeld = true, now = 1))
    }

    @Test fun hotspotFollowsRoutesTetherEventsAndUnsettledStates() {
        val policy = RootMaintenancePolicy(forceAfterMs = 1000)
        assertTrue(policy.hotspotSyncNeeded(true, HotspotState.DISABLED, now = 0))
        policy.routesSynced(routes, now = 0)
        policy.hotspotSynced(true, now = 0)
        assertFalse(policy.hotspotSyncNeeded(true, HotspotState.ACTIVE, now = 1))
        assertFalse(policy.hotspotSyncNeeded(true, HotspotState.DISABLED, now = 1))
        assertTrue("preference flipped", policy.hotspotSyncNeeded(false, HotspotState.ACTIVE, now = 1))
        assertTrue("waiting state keeps polling", policy.hotspotSyncNeeded(true, HotspotState.WAITING_HOTSPOT, now = 1))
        assertTrue("forced pass", policy.hotspotSyncNeeded(true, HotspotState.ACTIVE, now = 1000))
        policy.hotspotChanged()
        assertTrue("tether broadcast", policy.hotspotSyncNeeded(true, HotspotState.ACTIVE, now = 1))
        policy.hotspotSynced(true, now = 1)
        assertFalse(policy.hotspotSyncNeeded(true, HotspotState.ACTIVE, now = 2))
        assertTrue(policy.routeSyncNeeded(routes + "10.77.0.9/32", leaseHeld = true, now = 2))
        assertTrue("route change dirties hotspot", policy.hotspotSyncNeeded(true, HotspotState.ACTIVE, now = 2))
    }

    @Test fun intervalBacksOffOnlyWhenScreenIsOffAndPlanIsStable() {
        val policy = RootMaintenancePolicy()
        assertEquals(60_000L, policy.interval(interactive = false, now = 0))
        policy.routesSynced(routes, now = 0)
        policy.routeSyncNeeded(routes, leaseHeld = true, now = 1)
        assertEquals(60_000L, policy.interval(interactive = false, now = 1))
        policy.routeSyncNeeded(routes, leaseHeld = true, now = 2)
        assertEquals(120_000L, policy.interval(interactive = false, now = 2))
        assertEquals(60_000L, policy.interval(interactive = true, now = 2))
        policy.routeSyncNeeded(routes, leaseHeld = true, now = 3)
        assertEquals(240_000L, policy.interval(interactive = false, now = 3))
        repeat(20) { policy.routeSyncNeeded(routes, leaseHeld = true, now = 4) }
        assertEquals(299_996L, policy.interval(interactive = false, now = 4))
        assertEquals(1_000L, policy.interval(interactive = false, now = 299_000))
        policy.externalWake()
        policy.routeSyncNeeded(routes, leaseHeld = true, now = 5)
        assertEquals(60_000L, policy.interval(interactive = false, now = 5))
        policy.routeSyncNeeded(routes.take(1), leaseHeld = true, now = 6)
        assertEquals(60_000L, policy.interval(interactive = false, now = 6))
    }
}
