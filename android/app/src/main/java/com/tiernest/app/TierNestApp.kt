package com.tiernest.app

import android.app.Application
import com.tiernest.app.data.AppStore
import com.tiernest.app.engine.RootEngine
import kotlinx.coroutines.flow.MutableStateFlow

data class Dashboard(
    val phase: String = "已断开", val detail: String = "按需连接你的设备", val active: Boolean = false,
    val busy: Boolean = false, val cidr: String = "", val routeCount: Int = 0,
    val table: String = "", val priority: String = "", val vpn: Boolean = false,
    val peers: List<com.tiernest.app.data.Peer> = emptyList(), val samples: List<Pair<Float, Float>> = emptyList(),
    val rxRate: Float = 0f, val txRate: Float = 0f, val excluded: List<String> = emptyList(),
    val error: String = "", val updatedAt: Long = 0,
    val rxTotal: Long = 0, val txTotal: Long = 0, val uptimeSeconds: Long = 0,
    val connectionMode: com.tiernest.app.data.ConnectionMode = com.tiernest.app.data.ConnectionMode.VPN,
    val underlay: String = "",
)

class TierNestApp : Application() {
    lateinit var store: AppStore; private set
    lateinit var engine: RootEngine; private set
    lateinit var backups: com.tiernest.app.data.ConfigurationBackups; private set
    lateinit var vpnEngine: com.tiernest.app.engine.VpnEngine; private set
    val dashboard = MutableStateFlow(Dashboard())
    val uiVisible = MutableStateFlow(false)
    val uiDataVisible = MutableStateFlow(false)
    override fun onCreate() {
        super.onCreate()
        store = AppStore(this)
        engine = RootEngine(this)
        backups = com.tiernest.app.data.ConfigurationBackups(this)
        vpnEngine = com.tiernest.app.engine.VpnEngine(this)
    }
}
