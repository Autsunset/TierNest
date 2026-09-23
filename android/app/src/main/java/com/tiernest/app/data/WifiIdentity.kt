package com.tiernest.app.data

/** Shared, precompiled validators for Wi-Fi identity fields. */
object WifiIdentity {
    val iface = Regex("wlan[0-9]+")
    val mac = Regex("([0-9a-f]{2}:){5}[0-9a-f]{2}")
}
