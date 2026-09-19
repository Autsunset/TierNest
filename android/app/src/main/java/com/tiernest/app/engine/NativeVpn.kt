package com.tiernest.app.engine

/** JNI calls stay off the UI thread; the native core exposes no network RPC port. */
object NativeVpn {
    init { System.loadLibrary("tiernest_vpn") }
    @JvmStatic external fun validate(config: String): Int
    @JvmStatic external fun start(config: String): Int
    @JvmStatic external fun snapshot(): String
    @JvmStatic external fun setTunFd(fd: Int): Int
    @JvmStatic external fun stop(): Int
}
