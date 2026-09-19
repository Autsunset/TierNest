package com.tiernest.app.data

import android.content.Context
import android.os.Build
import android.provider.Settings

object DeviceName {
    fun current(context: Context): String = choose(
        runCatching { Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME) }.getOrNull(),
        Build.MANUFACTURER, Build.MODEL)

    /** Friendly public device settings only; no serial, Android ID, Bluetooth
     * permissions, network probes or persistent device identifier. */
    fun choose(systemName: String?, manufacturer: String?, model: String?): String {
        // The pinned EasyTier core broadcasts at most 32 Unicode code points.
        fun bounded(value: String) = buildString { value.codePoints().limit(32).forEach { appendCodePoint(it) } }
        fun usable(value: String?): String? = value?.map { if (it.isISOControl()) ' ' else it }
            ?.joinToString("")?.trim()?.takeUnless { name -> name.isBlank() ||
                listOf("unknown", "localhost", "localhost.localdomain", "android").any { it.equals(name, true) } }
        usable(systemName)?.let { return bounded(it) }
        val maker = usable(manufacturer)
        val device = usable(model)
        if (device != null) return bounded(if (maker == null || device.startsWith(maker, ignoreCase = true)) device else "$maker $device")
        return bounded(maker ?: "TierNest Android")
    }
}
