package com.tiernest.app.data

/** Main-thread/controller-lock confined. Skips privileged maintenance whose
 * inputs have not changed, so an idle connected phone does not re-run route
 * and iptables synchronisation every minute. A bounded forced pass still
 * re-verifies kernel state, and any change of inputs resyncs immediately. */
class RootMaintenancePolicy(
    private val forceAfterMs: Long = 300_000L,
    private val baseIntervalMs: Long = 60_000L,
    private val maxIntervalMs: Long = 300_000L,
) {
    private var syncedRoutes: List<String>? = null
    private var syncedAt = 0L
    private var hotspotEnabled: Boolean? = null
    private var hotspotAt = 0L
    private var hotspotDirty = true
    private var stableSamples = 0

    /** A backend stop or failure discards every assumption about kernel state. */
    fun reset() {
        syncedRoutes = null; syncedAt = 0; hotspotEnabled = null; hotspotAt = 0; hotspotDirty = true; stableSamples = 0
    }

    /** The system reported a tethering change; the privileged side must re-read it. */
    fun hotspotChanged() { hotspotDirty = true }

    fun routeSyncNeeded(routes: List<String>, leaseHeld: Boolean, now: Long): Boolean {
        val same = routes == syncedRoutes
        stableSamples = if (same) stableSamples + 1 else 0
        if (!same) hotspotDirty = true // Hotspot targets are derived from the routes.
        return !same || !leaseHeld || now - syncedAt >= forceAfterMs
    }

    fun routesSynced(routes: List<String>, now: Long) { syncedRoutes = routes; syncedAt = now }

    fun hotspotSyncNeeded(enabled: Boolean, state: HotspotState, now: Long): Boolean =
        hotspotDirty || enabled != hotspotEnabled ||
            (state != HotspotState.ACTIVE && state != HotspotState.DISABLED) || now - hotspotAt >= forceAfterMs

    fun hotspotSynced(enabled: Boolean, now: Long) { hotspotEnabled = enabled; hotspotAt = now; hotspotDirty = false }

    /** Screen on keeps the base cadence. With the screen off and the plan
     * stable, back off geometrically; screen-on and every event reconcile at once. */
    fun interval(interactive: Boolean): Long {
        if (interactive || stableSamples < 2) return baseIntervalMs
        return minOf(maxIntervalMs, baseIntervalMs shl minOf(stableSamples - 1, 8))
    }
}
