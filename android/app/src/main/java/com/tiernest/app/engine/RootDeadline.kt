package com.tiernest.app.engine

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.withTimeoutOrNull
import java.io.IOException

internal class RootCommandTimeoutException : IOException("Root communication timed out")

/** An operation deadline is a connection failure. Parent cancellation remains
 * cancellation, so explicit stop/lifecycle cleanup still interrupt correctly. */
internal suspend fun <T : Any> withRootDeadline(milliseconds: Long, block: suspend CoroutineScope.() -> T): T =
    withTimeoutOrNull(milliseconds, block) ?: throw RootCommandTimeoutException()
