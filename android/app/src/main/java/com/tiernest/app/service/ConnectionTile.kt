package com.tiernest.app.service

import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import com.tiernest.app.data.ConnectionMode
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.graphics.drawable.Icon
import com.tiernest.app.R
import com.tiernest.app.MainActivity
import com.tiernest.app.TierNestApp
import kotlinx.coroutines.*

class ConnectionTile : TileService() {
    private var scope: CoroutineScope? = null
    override fun onStartListening() {
        super.onStartListening()
        ConnectionService.refreshFromUserAction(this)
        scope?.cancel()
        scope = CoroutineScope(Dispatchers.Main + SupervisorJob()).also { owner ->
            owner.launch { (application as TierNestApp).dashboard.collect { state ->
                qsTile?.apply {
                    icon = Icon.createWithResource(this@ConnectionTile, R.drawable.ic_connection)
                    this.state = if ((application as TierNestApp).store.load().requested) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
                    if (Build.VERSION.SDK_INT >= 29) subtitle = state.phase
                    updateTile()
                }
            } }
        }
    }
    override fun onStopListening() { scope?.cancel(); scope = null; super.onStopListening() }
    override fun onClick() {
        super.onClick()
        if (isLocked) { unlockAndRun { toggle() }; return }
        toggle()
    }
    @android.annotation.SuppressLint("StartActivityAndCollapseDeprecated") // PendingIntent overload only exists on API 34+.
    private fun toggle() {
        val app = application as TierNestApp
        ConnectionService.refreshFromUserAction(this)
        val connect = !app.store.load().requested
        val mode = app.store.load().connectionMode
        if (connect && (runCatching { com.tiernest.app.data.ConfigCodec.effective(app.store.readConfig(), mode) }.isFailure ||
            (mode == ConnectionMode.VPN && VpnService.prepare(this) != null))) {
            if (mode == ConnectionMode.VPN) app.dashboard.value = app.dashboard.value.copy(detail = "首次连接请在 App 中授权系统 VPN")
            val intent = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (Build.VERSION.SDK_INT >= 34) startActivityAndCollapse(PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
            else { @Suppress("DEPRECATION") startActivityAndCollapse(intent) }
        } else ConnectionService.request(this, connect)
    }
    override fun onDestroy() { scope?.cancel(); super.onDestroy() }
}
