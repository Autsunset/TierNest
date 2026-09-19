package com.tiernest.app.service

import android.app.*
import android.content.*
import android.net.*
import android.os.*
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.tiernest.app.*
import com.tiernest.app.data.*
import com.tiernest.app.engine.EngineStatus
import com.tiernest.app.engine.VpnEngine
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class ConnectionService : VpnService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val events = Channel<Unit>(Channel.CONFLATED)
    private val operations = Mutex()
    private lateinit var app: TierNestApp
    private lateinit var detector: HomeDetector
    private lateinit var cm: ConnectivityManager
    private var registered = false
    private var screenRegistered = false
    private var eventHealthy = true
    private var signature = ""
    private var coreActive = false
    private var maintenance: Job? = null
    private var lastSample: Pair<Long, EngineStatus>? = null
    private var currentStartId = 0
    private var lastNotification = ""
    private val owner = java.util.UUID.randomUUID().toString()
    private var pendingReconnect = false
    private lateinit var vpnEngine: VpnEngine
    private var runningMode: ConnectionMode? = null
    private var coreStartedAt = 0L
    private var stopReason = ""

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) { events.trySend(Unit) }
        override fun onLost(network: Network) { events.trySend(Unit) }
        override fun onLinkPropertiesChanged(network: Network, props: LinkProperties) { events.trySend(Unit) }
        override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) { events.trySend(Unit) }
    }
    private val screen = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) { events.trySend(Unit) }
    }

    override fun onCreate() {
        super.onCreate()
        app = application as TierNestApp
        vpnEngine = app.vpnEngine
        activeService = this
        detector = HomeDetector(app)
        cm = getSystemService(ConnectivityManager::class.java)
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL, "组网连接", NotificationManager.IMPORTANCE_LOW))
        startForeground(1, notification("正在准备连接"))
        try {
            cm.registerNetworkCallback(NetworkRequest.Builder()
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_TRUSTED)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED).build(), callback)
            registered = true
        } catch (_: Exception) { eventHealthy = false }
        try {
            ContextCompat.registerReceiver(this, screen, IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_OFF); addAction(Intent.ACTION_SCREEN_ON)
            }, ContextCompat.RECEIVER_NOT_EXPORTED)
            screenRegistered = true
        } catch (_: Exception) { eventHealthy = false }
        scope.launch {
            try {
                for (ignored in events) {
                    delay(400) // Merge bursts of address, network and VPN callbacks.
                    try { operations.withLock { reconcile() } }
                    catch (cancelled: CancellationException) { throw cancelled }
                    catch (error: Exception) {
                        val cleanupError = runCatching { stopBackend() }.exceptionOrNull()
                        coreActive = false
                        app.store.update { it.copy(requested = false) }
                        app.dashboard.update { it.copy(phase = "连接失败", busy = false, active = false,
                            detail = "请检查下方错误后重试", cidr = "", table = "", priority = "", routeCount = 0,
                            error = (error.message ?: "连接失败，请重新连接") +
                                if (cleanupError != null) "；清理状态未确认，请重新打开 App 检查" else "",
                            peers = emptyList(), rxRate = 0f, txRate = 0f) }
                        // No indefinite retry loop after a core/route/root failure.
                        finishService()
                    }
                }
            } finally {
                withContext(NonCancellable) { runCatching { stopBackend() } }
            }
        }
        scope.launch {
            combine(app.uiVisible, app.uiDataVisible) { visible, dataVisible -> visible && dataVisible }.collectLatest { visible ->
                if (visible) while (isActive) {
                    if (coreActive && !app.dashboard.value.busy) runCatching { operations.withLock {
                        // Finish the bounded in-flight pipe exchange before pausing
                        // sampling; cancellation must not leave a partial RPC reply.
                        if (coreActive && app.store.load().requested) withContext(NonCancellable) { sample() }
                    } }
                        .onFailure { if (it !is CancellationException) events.trySend(Unit) }
                    delay(3000)
                }
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        activeService = this
        currentStartId = startId
        when (intent?.action) {
            STOP -> app.store.update { it.copy(requested = false) }
        }
        events.trySend(Unit)
        return START_NOT_STICKY
    }

    private suspend fun reconcile() {
        maintenance?.cancel()
        val prefs = app.store.load()
        val automatic = ModePolicy.automatic(prefs.connectionMode, prefs.automatic)
        var home = false
        var warning = if (!eventHealthy) "系统事件监听失败，保持核心运行；未修改检测模式" else ""
        if (prefs.requested && automatic && eventHealthy) {
            try { home = detector.check(prefs) }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) {
                warning = "家庭网络检测失败，保持核心运行：${error.message.orEmpty().take(200)}"
                // A transport/protocol failure may have closed the Root session.
                // Recreate it below instead of assuming the old core survived.
                if (coreActive && runningMode == ConnectionMode.ROOT && !app.engine.status().alive) {
                    coreActive = false; lastSample = null
                }
            }
        } else detector.reset()
        val desired = ConnectionPolicy.decide(app.store.load().requested, prefs.screenSuspend && screenRegistered,
            getSystemService(PowerManager::class.java).isInteractive, automatic, home, eventHealthy)
        if (desired == DesiredConnection.STOPPED) {
            app.dashboard.update { it.copy(phase = "正在断开", busy = true) }
            stopBackend(); coreActive = false; lastSample = null
            if (app.store.load().requested) { events.trySend(Unit); return }
            app.dashboard.value = Dashboard(error = stopReason)
            finishService()
            return
        }
        check(prefs.migrationReview.isEmpty()) { "导入的模块配置需要先在设置中确认兼容性" }
        if (desired != DesiredConnection.CONNECTED) {
            stopBackend(); coreActive = false; lastSample = null
            val phase = if (desired == DesiredConnection.HOME_STANDBY) "家庭网络待机" else "锁屏暂停"
            app.dashboard.update { it.copy(phase = phase, active = false, busy = false, error = warning,
                cidr = "", table = "", priority = "", routeCount = 0,
                detail = if (desired == DesiredConnection.HOME_STANDBY) "通过已验证的 Wi-Fi 访问组网" else "亮屏后尝试重新连接，现有传输已中断",
                peers = emptyList(), rxRate = 0f, txRate = 0f) }
            notifyState(phase)
        } else {
            val physical = detector.physicalSignature()
            if (coreActive && (signature != physical || pendingReconnect || runningMode != prefs.connectionMode)) {
                stopBackend(); coreActive = false; lastSample = null
            }
            pendingReconnect = false
            signature = physical
            if (!coreActive) {
                app.dashboard.update { it.copy(phase = "正在连接", detail = "启动核心并等待虚拟地址", busy = true, error = "") }
                notifyState("正在连接")
                val configuration = withContext(Dispatchers.IO) { app.store.readConfig() }
                runningMode = prefs.connectionMode
                if (runningMode == ConnectionMode.VPN) vpnEngine.start(configuration, owner)
                else app.engine.start(configuration, owner)
                coreStartedAt = SystemClock.elapsedRealtime()
                var ready = false
                for (attempt in 0 until 60) {
                    val latest = app.store.load()
                    if (!latest.requested || latest.connectionMode != runningMode) {
                        stopBackend(); events.trySend(Unit); return
                    }
                    val status = backendStatus()
                    if (!status.alive) error("EasyTier 核心已退出；请检查配置、Root 权限与 SELinux 限制")
                    if (status.cidr.isNotBlank()) { ready = true; break }
                    delay(500)
                }
                check(ready) { "未取得虚拟 IPv4；请检查节点连接和 DHCP 配置" }
                coreActive = true
            }
            sample(syncRoutes = true)
            app.dashboard.update { it.copy(phase = "核心运行", detail = if (runningMode == ConnectionMode.VPN)
                "系统 VPN 组网 · 无需 Root" else "Root 组网 · 可与系统 VPN 共存", busy = false, error = warning) }
            notifyState("核心运行")
        }
        // No periodic work in event-based home standby or screen standby.
        val interval = when {
            desired == DesiredConnection.SCREEN_STANDBY -> null
            automatic && prefs.detection == DetectionMode.HTTP -> prefs.interval.toLong() * 1000
            coreActive -> 60_000L
            else -> null
        }
        if (interval != null) maintenance = scope.launch { delay(interval); events.trySend(Unit) }
    }

    private suspend fun sample(syncRoutes: Boolean = false) {
        val status = backendStatus()
        check(status.alive) { "核心进程已退出" }
        val peerJson = if (runningMode == ConnectionMode.VPN) vpnEngine.peers() else app.engine.peers()
        val physical = withContext(Dispatchers.IO) { detector.physicalNetworks() }
        val (peers, plan) = withContext(Dispatchers.Default) {
            val peers = PeerCodec.decode(peerJson)
            peers to RoutePlanner.plan(status.cidr, peers, physical)
        }
        if (syncRoutes) {
            check(plan.routes.isNotEmpty()) { "虚拟网段与物理网络冲突，或没有可用的 IPv4 路由" }
            if (runningMode == ConnectionMode.VPN) vpnEngine.sync(this, plan.routes) else app.engine.sync(plan.routes)
        }
        val now = SystemClock.elapsedRealtime()
        val old = lastSample
        val seconds = if (old == null) 0f else (now - old.first) / 1000f
        val rx = if (seconds <= 0 || status.rx < (old?.second?.rx ?: 0)) 0f else (status.rx - (old?.second?.rx ?: status.rx)) / seconds
        val tx = if (seconds <= 0 || status.tx < (old?.second?.tx ?: 0)) 0f else (status.tx - (old?.second?.tx ?: status.tx)) / seconds
        val sampleVisible = app.uiVisible.value && app.uiDataVisible.value
        lastSample = if (sampleVisible) now to status else null
        val routing = if (syncRoutes) backendStatus() else status
        app.dashboard.update { it.copy(active = true, cidr = status.cidr, peers = peers, rxRate = rx, txRate = tx,
            samples = if (sampleVisible) (it.samples + (rx to tx)).takeLast(40) else it.samples,
            routeCount = plan.routes.size, table = routing.table,
            priority = routing.priority, vpn = detector.vpnActive(), excluded = plan.excluded, updatedAt = System.currentTimeMillis(),
            rxTotal = status.rx, txTotal = status.tx, uptimeSeconds = (now - coreStartedAt).coerceAtLeast(0) / 1000,
            connectionMode = runningMode ?: app.store.load().connectionMode,
            underlay = detector.networkLabel()) }
    }

    private suspend fun backendStatus() = if (runningMode == ConnectionMode.VPN) vpnEngine.status() else app.engine.status()
    private suspend fun stopBackend() {
        when (runningMode) {
            ConnectionMode.VPN -> vpnEngine.stop(owner)
            ConnectionMode.ROOT -> app.engine.stop(owner)
            null -> Unit
        }
        runningMode = null
        coreStartedAt = 0
    }
    private fun finishService() {
        if (activeService === this) activeService = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelfResult(currentStartId)
    }

    private fun notification(text: String): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val stop = PendingIntent.getService(this, 1, Intent(this, ConnectionService::class.java).setAction(STOP), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return NotificationCompat.Builder(this, CHANNEL).setSmallIcon(R.drawable.ic_tiernest)
            .setContentTitle("TierNest · $text").setContentText("点按管理连接").setContentIntent(open)
            .setOngoing(true).setSilent(true).addAction(0, "断开并停止", stop).build()
    }
    private fun notifyState(text: String) {
        if (lastNotification == text) return
        lastNotification = text
        getSystemService(NotificationManager::class.java).notify(1, notification(text))
    }

    override fun onDestroy() {
        if (activeService === this) activeService = null
        if (registered) runCatching { cm.unregisterNetworkCallback(callback) }
        if (screenRegistered) runCatching { unregisterReceiver(screen) }
        scope.cancel()
        super.onDestroy()
    }
    override fun onBind(intent: Intent?) = super.onBind(intent)
    override fun onRevoke() {
        // Revoke can arrive on a Binder thread and from an old VPN session.
        scope.launch {
            if (runningMode == ConnectionMode.VPN && app.store.load().connectionMode == ConnectionMode.VPN) {
                stopReason = "VPN 连接已被系统撤销；可能启用了其他 VPN"
                request(this@ConnectionService, false)
            }
        }
    }

    companion object {
        const val START = "com.tiernest.app.START"
        const val STOP = "com.tiernest.app.STOP"
        const val RECONCILE = "com.tiernest.app.RECONCILE"
        private const val CHANNEL = "connection"
        private var activeService: ConnectionService? = null
        fun request(context: Context, connect: Boolean) {
            val app = context.applicationContext as TierNestApp
            if (connect && app.store.load().connectionMode == ConnectionMode.VPN && VpnService.prepare(context) != null) {
                app.dashboard.update { it.copy(error = "请打开 App 并授权 VPN 连接") }
                return
            }
            // Persist stop before waiting for any running root command or callback.
            app.store.update { it.copy(requested = connect) }
            activeService?.let { it.events.trySend(Unit); return }
            if (!connect) { app.dashboard.value = Dashboard(); return }
            // This intent only reconciles the latest persisted choice. An older
            // queued start intent must never undo a later manual stop.
            try { ContextCompat.startForegroundService(context, Intent(context, ConnectionService::class.java).setAction(RECONCILE)) }
            catch (error: Exception) {
                app.store.update { it.copy(requested = false) }
                app.dashboard.update { it.copy(error = "系统拒绝启动服务，请打开 App 操作：${error.javaClass.simpleName}") }
            }
        }
        fun settingsChanged(context: Context) {
            val app = context.applicationContext as TierNestApp
            if (app.store.load().requested) {
                activeService?.let { it.events.trySend(Unit); return }
                ContextCompat.startForegroundService(context, Intent(context, ConnectionService::class.java).setAction(RECONCILE))
            }
        }
        fun reconnect(context: Context) {
            val app = context.applicationContext as TierNestApp
            if (!app.store.load().requested) return // A manual stop during save always wins.
            activeService?.let { it.pendingReconnect = true; it.events.trySend(Unit); return }
            settingsChanged(context)
        }
    }
}
