package com.tiernest.app.engine

import android.net.VpnService
import android.content.Context
import android.os.Build
import android.os.ParcelFileDescriptor
import android.system.OsConstants
import com.tiernest.app.data.*
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject

data class NativeSnapshot(val status: EngineStatus, val peersJson: String, val failed: Boolean = false)

object NativeSnapshotCodec {
    fun decode(text: String): NativeSnapshot {
        val data = JSONObject(text)
        return NativeSnapshot(EngineStatus(data.optBoolean("alive"), data.optString("cidr"),
            data.optLong("rx").coerceAtLeast(0), data.optLong("tx").coerceAtLeast(0)),
            data.optJSONArray("peers")?.toString() ?: "[]", data.optBoolean("failed"))
    }
}

class VpnEngine(private val context: Context) {
    private val mutex = Mutex()
    private var owner: String? = null
    private var started = false
    private var descriptor: ParcelFileDescriptor? = null
    private var applied = ""
    private var mtu = 1380
    private var snapshot = NativeSnapshot(EngineStatus(), "[]")

    suspend fun start(config: String, nextOwner: String) = mutex.withLock {
        withContext(Dispatchers.IO) {
            check(VpnService.prepare(context) == null) { "请先在 App 中授权 VPN 连接" }
            stopLocked()
            val effective = ConfigCodec.effective(config, ConnectionMode.VPN, DeviceName.current(context))
            mtu = ConfigCodec.form(effective).mtu.toInt() // Validated together with the native configuration.
            NativeVpn.validate(effective)
            NativeVpn.start(effective)
            started = true; owner = nextOwner
            applied = ""
        }
    }

    suspend fun status(): EngineStatus = mutex.withLock {
        if (!started) return@withLock EngineStatus()
        snapshot = withContext(Dispatchers.IO) { NativeSnapshotCodec.decode(NativeVpn.snapshot()) }
        check(!snapshot.failed) { "EasyTier VPN 实例退出，请检查网络配置" }
        snapshot.status
    }

    suspend fun peers(): String = mutex.withLock { snapshot.peersJson }

    suspend fun sync(service: VpnService, routes: List<String>) = mutex.withLock {
        withContext(Dispatchers.IO + NonCancellable) {
            check(started && snapshot.status.alive) { "VPN 内核未运行" }
            val address = snapshot.status.cidr
            check(RoutePlanner.cidr(address) != null) { "尚未取得 VPN 虚拟地址" }
            check(routes.isNotEmpty() && routes.all { RoutePlanner.cidr(it)?.let(RoutePlanner::safe) == true }) { "没有可用的 VPN IPv4 路由" }
            // Joining/leaving a peer within an already routed virtual subnet
            // must not recreate the system VPN interface unnecessarily.
            val normalized = RoutePlanner.minimalRoutes(routes)
            val signature = "$address|$mtu|${normalized.joinToString(",")}"
            if (signature == applied && descriptor != null) return@withContext
            check(VpnService.prepare(service) == null) { "VPN 授权已被撤销" }
            val builder = service.Builder().setSession("TierNest").setMtu(mtu).setBlocking(false)
                .addAddress(address.substringBefore('/'), address.substringAfter('/', "32").toInt())
                .allowFamily(OsConstants.AF_INET6)
                // All Rust sockets share this UID. Excluding it keeps transport
                // sockets on the underlay and prevents recursive VPN tunneling.
                .addDisallowedApplication(service.packageName)
            normalized.forEach { builder.addRoute(it.substringBefore('/'), it.substringAfter('/').toInt()) }
            if (Build.VERSION.SDK_INT >= 29) builder.setMetered(false)
            val replacement = builder.establish() ?: error("系统未建立 VPN 接口，请重新授权")
            try {
                NativeVpn.setTunFd(replacement.fd) // Native waits for TunDeviceReady.
                val previous = descriptor
                descriptor = replacement
                applied = signature
                previous?.close()
            } catch (error: Exception) {
                // A timed-out handoff may still be queued. Stop native users of
                // both descriptors before releasing either file descriptor.
                stopLocked()
                replacement.close()
                throw error
            }
        }
    }

    suspend fun stop(expectedOwner: String? = null) = mutex.withLock {
        if (expectedOwner != null && owner != expectedOwner) return@withLock
        withContext(Dispatchers.IO + NonCancellable) { stopLocked() }
    }

    private fun stopLocked() {
        try { if (started) NativeVpn.stop() } finally {
            descriptor?.close(); descriptor = null; started = false; owner = null
            applied = ""; snapshot = NativeSnapshot(EngineStatus(), "[]")
        }
    }
}
