package com.tiernest.app.engine

import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import java.io.IOException
import java.io.Reader

/** A broken su pipe is a command failure, not an unhandled launch exception.
 * Both line length and buffered output are bounded even if a manager is noisy. */
internal class RootOutputPump(reader: Reader, scope: CoroutineScope,
                              private val onFailure: (Exception) -> Unit,
                              maxLineChars: Int = 64 * 1024) {
    val lines = Channel<String>(16)
    init {
        scope.launch(Dispatchers.IO) {
            try {
                reader.use {
                    val buffer = CharArray(4096)
                    val line = StringBuilder()
                    while (true) {
                        val count = it.read(buffer)
                        if (count < 0) { if (line.isNotEmpty()) lines.send(line.toString().trimEnd('\r')); break }
                        for (index in 0 until count) {
                            val char = buffer[index]
                            if (char == '\n') { lines.send(line.toString().trimEnd('\r')); line.setLength(0) }
                            else {
                                if (line.length >= maxLineChars) throw IOException("Root output line exceeded the limit")
                                line.append(char)
                            }
                        }
                    }
                }
            } catch (cancelled: CancellationException) {
                lines.close(cancelled)
                throw cancelled
            } catch (error: Exception) {
                runCatching { onFailure(error) }
                lines.close(error)
            } finally { lines.close() }
        }
    }
}
