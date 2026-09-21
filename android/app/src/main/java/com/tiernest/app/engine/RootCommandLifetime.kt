package com.tiernest.app.engine

/** Temporary sessions always close. A framed read-only operation failure may
 * retain an existing connection; transport failures and cancellation may not. */
internal suspend fun <T> withRootCommandLifetime(
    ephemeral: Boolean,
    retain: Boolean,
    preserveOnOperationFailure: Boolean,
    close: suspend () -> Unit,
    block: suspend () -> T,
): T {
    var success = false
    var failure: Throwable? = null
    try {
        return block().also { success = true }
    } catch (error: RootOperationException) {
        success = preserveOnOperationFailure
        failure = error
        throw error
    } catch (error: Throwable) {
        failure = error
        throw error
    } finally {
        if (!success || (ephemeral && !retain)) {
            try { close() } catch (cleanup: Exception) {
                if (failure != null) failure.addSuppressed(cleanup) else throw cleanup
            }
        }
    }
}
