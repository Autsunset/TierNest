package com.tiernest.app.data

/** One failed HTTP check is tolerated only on the same continuously observed
 * Wi-Fi link and target. A disconnect, exception or second failure revokes it. */
class HomeTrust {
    private var trusted: String? = null
    private var failedOnce = false

    fun observe(identity: String, reachable: Boolean): Boolean {
        if (reachable) { trusted = identity; failedOnce = false; return true }
        if (trusted == identity && !failedOnce) { failedOnce = true; return true }
        return reset()
    }

    fun reset(): Boolean { trusted = null; failedOnce = false; return false }
}
