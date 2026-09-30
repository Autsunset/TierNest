package com.tiernest.app.data

/** Overview counters remain live without spawning a privileged peer CLI on
 * every tick. Node-page sampling and route maintenance always refresh now. */
class TopologyRefreshPolicy(private val intervalMs: Long = 15_000L) {
    private var refreshedAt: Long? = null
    fun needed(now: Long, force: Boolean = false): Boolean =
        force || refreshedAt?.let { now - it >= intervalMs } != false
    fun refreshed(now: Long) { refreshedAt = now }
    fun reset() { refreshedAt = null }
}
