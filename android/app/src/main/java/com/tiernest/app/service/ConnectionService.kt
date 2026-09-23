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
import com.tiernest.app.engine.RootCommandTimeoutException
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import com.tiernest.app.diagnostics.LogEvent

class ConnectionService : VpnService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val events = Channel<Unit>(Channel.CONFLATED)
    private val operations = Mutex()
    private lateinit var app: TierNestApp
    private lateinit var detector: HomeDetector
    private lateinit var cm: ConnectivityManager
    private var registered = false
    private var screenRegistered = false
    private var tetherRegistered = false
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
    private var loggedPhase: DesiredConnection? = null
    private val recovery = RootRecoveryPolicy()
    private val maintenancePolicy = RootMaintenancePolicy()
    private val externalWakePending = java.util.concurrent.atomic.AtomicBoolean(false)
    // Delivered on the connectivity thread. Signal-strength and metering
    // updates arrive constantly; only changes the reconcile logic can observe
    // (transport, VPN/internet/validated bits, link properties) wake it.
    private val capabilityKeys = java.util.concurrent.ConcurrentHashMap<Network, String>()
    private var requestRevision = 0L
    private var operationDesired: DesiredConnection? = null

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) { signalEvent() }
        override fun onLost(network: Network) { capabilityKeys.remove(network); signalEvent() }
        override fun onLinkPropertiesChanged(network: Network, props: LinkProperties) { signalEvent() }
        override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
            val key = buildString {
                for (transport in intArrayOf(NetworkCapabilities.TRANSPORT_WIFI, NetworkCapabilities.TRANSPORT_CELLULAR,
                    NetworkCapabilities.TRANSPORT_ETHERNET, NetworkCapabilities.TRANSPORT_VPN)) append(if (caps.hasTransport(transport)) '1' else '0')
                for (capability in intArrayOf(NetworkCapabilities.NET_CAPABILITY_NOT_VPN, NetworkCapabilities.NET_CAPABILITY_INTERNET,
                    NetworkCapabilities.NET_CAPABILITY_VALIDATED)) append(if (caps.hasCapability(capability)) '1' else '0')
            }
            if (capabilityKeys.put(network, key) != key) signalEvent()
        }
    }
    private val screen = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) { signalEvent() }
    }
    // A cue only: the privileged command independently reads live tether state,
    // so an intent never supplies an interface or a route to install.
    private val tether = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (app.store.load().hotspotAccess) { maintenancePolicy.hotspotChanged(); signalEvent() }
        }
    }

    private fun signalEvent() {
        externalWakePending.set(true)
        events.trySend(Unit)
    }

    override fun onCreate() {
        super.onCreate()
        app = application as TierNestApp
        vpnEngine = app.vpnEngine
        activeService = this
        pendingStart = null
        app.diagnostics.event(LogEvent.SERVICE_CREATE)
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
        } catch (error: Exception) { eventHealthy = false; app.diagnostics.event(LogEvent.EVENT_SOURCE_FAILED, error) }
        try {
            ContextCompat.registerReceiver(this, tether, IntentFilter("android.net.conn.TETHER_STATE_CHANGED"),
                ContextCompat.RECEIVER_EXPORTED)
            tetherRegistered = true
        } catch (error: Exception) { app.diagnostics.event(LogEvent.EVENT_SOURCE_FAILED, error) }
        try {
            ContextCompat.registerReceiver(this, screen, IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_OFF); addAction(Intent.ACTION_SCREEN_ON)
            }, ContextCompat.RECEIVER_NOT_EXPORTED)
            screenRegistered = true
        } catch (error: Exception) { eventHealthy = false; app.diagnostics.event(LogEvent.EVENT_SOURCE_FAILED, error) }
        scope.launch {
            try {
                for (ignored in events) {
                    delay(400) // Merge bursts of address, network and VPN callbacks.
                    operations.withLock {
                        if (externalWakePending.getAndSet(false)) maintenancePolicy.externalWake()
                        attempt { reconcile() }
                    }
                }
            } finally {
                withContext(NonCancellable) { operations.withLock { runCatching { stopBackend() } } }
            }
        }
        scope.launch {
            combine(app.uiVisible, app.uiDataVisible) { visible, dataVisible -> visible && dataVisible }.collectLatest { visible ->
                if (visible) while (isActive) {
                    if (coreActive && !app.dashboard.value.busy) runCatching { operations.withLock {
                        // Finish the bounded in-flight pipe exchange before pausing
                        // sampling; cancellation must not leave a partial RPC reply.
                        if (coreActive && app.store.load().requested) withContext(NonCancellable) {
                            attempt { sample() }
                        }
                    } }
                        .onFailure { if (it !is CancellationException) signalEvent() }
                    delay(3000)
                }
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        activeService = this
        currentStartId = startId
        app.diagnostics.event(LogEvent.SERVICE_START, mode = app.store.load().connectionMode.name)
        when (intent?.action) {
            STOP -> {
                app.diagnostics.event(LogEvent.STOP_REQUEST, mode = app.store.load().connectionMode.name)
                stopReason = ""
                requestRevision++
                app.store.update { it.copy(requested = false, lastConnectionError = "") }
            }
        }
        if (app.store.load().requested) app.store.update { it.copy(
            sessionStartedAt = System.currentTimeMillis(), sessionProcessId = android.os.Process.myPid()) }
        signalEvent()
        // Recover a system-killed foreground service; explicit stop and core
        // failures persist requested=false and call stopSelf, so never loop.
        return START_STICKY
    }

    /** Both callers hold operations for the exchange AND its cleanup/recovery.
     * Otherwise UI sampling can run while an old session is being torn down. */
    private suspend fun attempt(block: suspend () -> Unit) {
        val revision = requestRevision
        operationDesired = null
        try { block() }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (error: Exception) { handleFailure(error, revision) }
    }

    private suspend fun handleFailure(error: Exception, revision: Long) {
        val failedMode = runningMode
        coreActive = false
        lastSample = null
        maintenance?.cancel()
        app.diagnostics.event(LogEvent.CONNECTION_FAILED, error, mode = failedMode?.name)
        val cleanupError = runCatching { stopBackend() }.exceptionOrNull()
        // RootEngine closes a poisoned pipe before propagating the original
        // error. Its suppressed cleanup errors must also prevent a retry.
        val cleanupSucceeded = cleanupError == null &&
            generateSequence<Throwable>(error) { it.cause }.take(8).all { it.suppressed.isEmpty() }
        val latest = app.store.load()
        val standby = ConnectionPolicy.decide(latest.requested, latest.screenSuspend && screenRegistered,
            getSystemService(PowerManager::class.java).isInteractive,
            ModePolicy.automatic(latest.connectionMode, latest.automatic), false, eventHealthy) != DesiredConnection.CONNECTED ||
            (operationDesired == DesiredConnection.HOME_STANDBY &&
                ModePolicy.automatic(latest.connectionMode, latest.automatic) && eventHealthy)
        val decision = recovery.decide(latest.requested, latest.connectionMode, failedMode,
            revision != requestRevision, error is RootCommandTimeoutException, cleanupSucceeded, standby)
        app.diagnostics.event(LogEvent.ROOT_RECOVERY, mode = failedMode?.name, recovery = decision)
        val cleanupWarning = if (!cleanupSucceeded) "；清理状态未确认，请重新打开 App 检查" else ""
        when (decision) {
            RecoveryDecision.STOPPED -> {
                app.dashboard.value = Dashboard(error = stopReason + cleanupWarning)
                finishService()
            }
            RecoveryDecision.RECONCILE, RecoveryDecision.RETRY -> {
                app.dashboard.value = Dashboard(phase = "正在恢复连接", busy = true,
                    detail = if (decision == RecoveryDecision.RETRY) "Root 通信超时，正在尝试一次重连" else "正在应用最新运行设置")
                notifyState("正在恢复连接")
                // A single, non-waking delay. Keep the operation lock so network
                // callbacks cannot bypass the backoff; manual stop persists now.
                if (decision == RecoveryDecision.RETRY) delay(1500)
                signalEvent() // Re-read stop/mode/screen/home before starting.
            }
            RecoveryDecision.FAILED -> {
                val message = (error.message ?: "连接失败，请重新连接") + cleanupWarning
                app.store.update { it.copy(requested = false, lastConnectionError = message) }
                app.dashboard.value = Dashboard(phase = "连接失败", detail = "请检查下方错误后重试", error = message)
                finishService()
            }
        }
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
                if (error is RootCommandTimeoutException && coreActive && runningMode == ConnectionMode.ROOT) throw error
                warning = "家庭网络检测失败，保持核心运行：${error.message.orEmpty().take(200)}"
                // A transport/protocol failure may have closed the Root session.
                // Recreate it below instead of assuming the old core survived.
                if (coreActive && runningMode == ConnectionMode.ROOT && !app.engine.status().alive) {
                    coreActive = false; lastSample = null
                }
            }
        } else detector.reset()
        val interactive = getSystemService(PowerManager::class.java).isInteractive
        val desired = ConnectionPolicy.decide(app.store.load().requested, prefs.screenSuspend && screenRegistered,
            interactive, automatic, home, eventHealthy)
        operationDesired = desired
        recovery.reconcile(desired)
        if (desired != loggedPhase) {
            when (desired) {
                DesiredConnection.HOME_STANDBY -> app.diagnostics.event(LogEvent.HOME_STANDBY)
                DesiredConnection.SCREEN_STANDBY -> app.diagnostics.event(LogEvent.SCREEN_STANDBY)
                else -> Unit
            }
            loggedPhase = desired
        }
        if (desired == DesiredConnection.STOPPED) {
            app.dashboard.update { it.copy(phase = "正在断开", busy = true) }
            stopBackend(); coreActive = false; lastSample = null
            if (app.store.load().requested) { signalEvent(); return }
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
                app.diagnostics.event(LogEvent.NETWORK_CHANGED, mode = runningMode?.name)
                stopBackend(); coreActive = false; lastSample = null
            }
            pendingReconnect = false
            signature = physical
            if (!coreActive) {
                app.dashboard.update { it.copy(phase = "正在连接", detail = "启动核心并等待虚拟地址", busy = true, error = "") }
                notifyState("正在连接")
                val configuration = withContext(Dispatchers.IO) { app.store.readConfig() }
                val latest = app.store.load()
                val latestDesired = ConnectionPolicy.decide(latest.requested, latest.screenSuspend && screenRegistered,
                    getSystemService(PowerManager::class.java).isInteractive,
                    ModePolicy.automatic(latest.connectionMode, latest.automatic), home, eventHealthy)
                recovery.reconcile(latestDesired)
                if (latestDesired != DesiredConnection.CONNECTED || latest.connectionMode != prefs.connectionMode) {
                    signalEvent(); return
                }
                runningMode = prefs.connectionMode
                recovery.starting(prefs.connectionMode)
                app.diagnostics.event(LogEvent.CORE_START, mode = runningMode?.name)
                if (runningMode == ConnectionMode.VPN) vpnEngine.start(configuration, owner)
                else app.engine.start(configuration, owner)
                coreStartedAt = SystemClock.elapsedRealtime()
                var ready = false
                for (attempt in 0 until 60) {
                    val latest = app.store.load()
                    if (!latest.requested || latest.connectionMode != runningMode) {
                        stopBackend(); signalEvent(); return
                    }
                    val status = backendStatus()
                    if (!status.alive) error("EasyTier 核心已退出；请检查配置、Root 权限与 SELinux 限制")
                    if (status.cidr.isNotBlank()) { ready = true; break }
                    delay(500)
                }
                check(ready) { "未取得虚拟 IPv4；请检查节点连接和 DHCP 配置" }
                coreActive = true
                app.diagnostics.event(LogEvent.CORE_READY, mode = runningMode?.name)
            }
            sample(syncRoutes = true)
            runningMode?.let(recovery::connected)
            app.dashboard.update { it.copy(phase = "核心运行", detail = if (runningMode == ConnectionMode.VPN)
                "系统 VPN 组网 · 无需 Root" else "Root 组网 · 可与系统 VPN 共存", busy = false, error = warning) }
            notifyState("核心运行")
        }
        // No periodic work in event-based home standby or screen standby.
        val interval = when {
            desired == DesiredConnection.SCREEN_STANDBY -> null
            automatic && prefs.detection == DetectionMode.HTTP -> prefs.interval.toLong() * 1000
            coreActive -> maintenancePolicy.interval(interactive, SystemClock.elapsedRealtime())
            else -> null
        }
        if (interval != null) maintenance = scope.launch { delay(interval); events.trySend(Unit) }
    }

    private suspend fun sample(syncRoutes: Boolean = false) {
        val status = backendStatus()
        check(status.alive) { "核心进程已退出" }
        val peerJson = if (runningMode == ConnectionMode.VPN) vpnEngine.peers() else app.engine.peers()
        val network = withContext(Dispatchers.IO) { detector.observe() }
        val (peers, plan) = withContext(Dispatchers.Default) {
            val peers = PeerCodec.decode(peerJson)
            peers to RoutePlanner.plan(status.cidr, peers, network.physicalNetworks)
        }
        var synced = false
        if (syncRoutes) {
            check(plan.routes.isNotEmpty()) { "虚拟网段与物理网络冲突，或没有可用的 IPv4 路由" }
            // VpnEngine short-circuits an unchanged signature itself. The Root
            // journal sync and hotspot rules are re-driven only when their inputs
            // changed, the lease vanished, or a bounded forced pass is due.
            val clock = SystemClock.elapsedRealtime()
            val leaseHeld = runningMode != ConnectionMode.ROOT || status.table.isNotBlank()
            val routeSyncNeeded = maintenancePolicy.routeSyncNeeded(plan.routes, leaseHeld, clock)
            if (runningMode == ConnectionMode.VPN) {
                vpnEngine.sync(this, plan.routes)
                maintenancePolicy.routesSynced(plan.routes, clock)
            } else {
                if (routeSyncNeeded) {
                    app.engine.sync(plan.routes)
                    maintenancePolicy.routesSynced(plan.routes, clock)
                    synced = true
                }
                val latest = app.store.load()
                val enabled = latest.requested && latest.hotspotAccess
                if ((latest.hotspotAccess || app.dashboard.value.hotspot != HotspotState.DISABLED) &&
                    maintenancePolicy.hotspotSyncNeeded(enabled, app.dashboard.value.hotspot, clock)) {
                    app.engine.hotspot(enabled)
                    maintenancePolicy.hotspotSynced(enabled, clock)
                    synced = true
                }
            }
        }
        val now = SystemClock.elapsedRealtime()
        val old = lastSample
        val seconds = if (old == null) 0f else (now - old.first) / 1000f
        val rx = if (seconds <= 0 || status.rx < (old?.second?.rx ?: 0)) 0f else (status.rx - (old?.second?.rx ?: status.rx)) / seconds
        val tx = if (seconds <= 0 || status.tx < (old?.second?.tx ?: 0)) 0f else (status.tx - (old?.second?.tx ?: status.tx)) / seconds
        val sampleVisible = app.uiVisible.value && app.uiDataVisible.value
        lastSample = if (sampleVisible) now to status else null
        val routing = if (synced) backendStatus() else status
        if (routing.hotspot != app.dashboard.value.hotspot) {
            app.diagnostics.event(LogEvent.HOTSPOT_STATE_CHANGED, mode = runningMode?.name, code = routing.hotspot.ordinal)
        }
        app.dashboard.update { it.copy(active = true, cidr = status.cidr, peers = peers, rxRate = rx, txRate = tx,
            samples = if (sampleVisible) (it.samples + (rx to tx)).takeLast(40) else it.samples,
            routeCount = plan.routes.size, table = routing.table,
            priority = routing.priority, vpn = network.vpnActive, excluded = plan.excluded, updatedAt = System.currentTimeMillis(),
            rxTotal = status.rx, txTotal = status.tx, uptimeSeconds = (now - coreStartedAt).coerceAtLeast(0) / 1000,
            connectionMode = runningMode ?: app.store.load().connectionMode,
            underlay = network.label, hotspot = routing.hotspot) }
    }

    private suspend fun backendStatus() = if (runningMode == ConnectionMode.VPN) vpnEngine.status() else app.engine.status()
    private suspend fun stopBackend() {
        coreActive = false
        lastSample = null
        maintenancePolicy.reset()
        if (runningMode != null) app.diagnostics.event(LogEvent.CORE_STOP, mode = runningMode?.name)
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
        return NotificationCompat.Builder(this, CHANNEL).setSmallIcon(R.drawable.ic_connection)
            .setContentTitle("TierNest · $text").setContentText("点按管理连接").setContentIntent(open)
            .setOngoing(true).setSilent(true).addAction(0, "断开并停止", stop).build()
    }
    private fun notifyState(text: String) {
        if (lastNotification == text) return
        lastNotification = text
        getSystemService(NotificationManager::class.java).notify(1, notification(text))
    }

    override fun onDestroy() {
        app.diagnostics.event(LogEvent.SERVICE_DESTROY, mode = runningMode?.name)
        if (activeService === this) {
            activeService = null
            var message = app.store.load().lastConnectionError
            if (app.store.load().requested) {
                message = "连接服务已停止；可直接重新连接"
                app.store.update { it.copy(requested = false, lastConnectionError = message) }
            }
            app.dashboard.value = Dashboard(error = message)
        }
        if (registered) runCatching { cm.unregisterNetworkCallback(callback) }
        if (screenRegistered) runCatching { unregisterReceiver(screen) }
        if (tetherRegistered) runCatching { unregisterReceiver(tether) }
        scope.cancel()
        super.onDestroy()
    }
    override fun onBind(intent: Intent?) = super.onBind(intent)
    override fun onRevoke() {
        // Revoke can arrive on a Binder thread and from an old VPN session.
        scope.launch {
            if (runningMode == ConnectionMode.VPN && app.store.load().connectionMode == ConnectionMode.VPN) {
                app.diagnostics.event(LogEvent.VPN_REVOKED)
                stopReason = "VPN 连接已被系统撤销；可能启用了其他 VPN"
                request(this@ConnectionService, false, stopReason)
            }
        }
    }

    companion object {
        const val START = "com.tiernest.app.START"
        const val STOP = "com.tiernest.app.STOP"
        const val RECONCILE = "com.tiernest.app.RECONCILE"
        private const val CHANNEL = "connection"
        private var activeService: ConnectionService? = null
        private var pendingStart: Any? = null

        /** Called on foreground entry or a tile interaction, not at Application
         * startup: BootReceiver must still see the persisted resume preference. */
        fun refreshFromUserAction(context: Context) {
            val app = context.applicationContext as TierNestApp
            activeService?.let { it.signalEvent(); return }
            if (pendingStart != null) return
            val previous = app.store.load()
            if (previous.requested) {
                app.diagnostics.event(LogEvent.ORPHANED_REQUEST, mode = previous.connectionMode.name)
                val reason = ConnectionExitReason.previous(context, previous)
                app.store.update { it.copy(requested = false, lastConnectionError = reason) }
                app.dashboard.value = Dashboard(error = reason)
            }
        }

        fun request(context: Context, connect: Boolean, stopMessage: String = "") {
            val app = context.applicationContext as TierNestApp
            app.diagnostics.event(if (connect) LogEvent.CONNECT_REQUEST else LogEvent.STOP_REQUEST,
                mode = app.store.load().connectionMode.name)
            if (connect && app.store.load().connectionMode == ConnectionMode.VPN && VpnService.prepare(context) != null) {
                app.dashboard.update { it.copy(error = "请打开 App 并授权 VPN 连接") }
                return
            }
            // Persist stop before waiting for any running root command or callback.
            app.store.update { it.copy(requested = connect, lastConnectionError = if (connect) "" else stopMessage) }
            activeService?.let { it.requestRevision++; it.stopReason = stopMessage; it.signalEvent(); return }
            if (!connect) { pendingStart = null; app.dashboard.value = Dashboard(error = stopMessage); return }
            if (pendingStart != null) return
            val ticket = Any()
            pendingStart = ticket
            app.dashboard.value = Dashboard(phase = "正在准备连接", detail = "正在启动连接服务", busy = true)
            // This intent only reconciles the latest persisted choice. An older
            // queued start intent must never undo a later manual stop.
            try { ContextCompat.startForegroundService(context, Intent(context, ConnectionService::class.java).setAction(RECONCILE)) }
            catch (error: Exception) {
                app.diagnostics.event(LogEvent.CONNECTION_FAILED, error)
                pendingStart = null
                val message = "系统拒绝启动服务，请打开 App 操作：${error.javaClass.simpleName}"
                app.store.update { it.copy(requested = false, lastConnectionError = message) }
                app.dashboard.value = Dashboard(error = message)
            }
            Handler(Looper.getMainLooper()).postDelayed({
                if (pendingStart === ticket && activeService == null) {
                    pendingStart = null
                    if (app.store.load().requested) {
                        val message = "系统未能启动连接服务；请重新连接"
                        app.store.update { it.copy(requested = false, lastConnectionError = message) }
                        app.dashboard.value = Dashboard(error = message)
                    }
                }
            }, 15_000)
        }
        fun settingsChanged(context: Context) {
            val app = context.applicationContext as TierNestApp
            if (app.store.load().requested) {
                activeService?.let { it.signalEvent(); return }
                request(context, true)
            }
        }
        fun reconnect(context: Context) {
            val app = context.applicationContext as TierNestApp
            if (!app.store.load().requested) return // A manual stop during save always wins.
            activeService?.let { it.requestRevision++; it.pendingReconnect = true; it.signalEvent(); return }
            settingsChanged(context)
        }
    }
}
