package com.tiernest.app

import android.Manifest
import android.os.Build
import android.os.Bundle
import android.app.Activity
import android.net.VpnService
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.runtime.*
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.core.view.WindowCompat
import com.tiernest.app.data.ColorMode
import com.tiernest.app.data.ConnectionMode
import com.tiernest.app.ui.TierNestTheme
import com.tiernest.app.ui.TierNestScreen

class MainActivity : ComponentActivity() {
    private val model: AppModel by viewModels()
    private var pendingStart = false
    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) {
        if (pendingStart) { pendingStart = false; authorizeAndConnect() }
    }
    private val vpnPermission = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        if (result.resultCode == Activity.RESULT_OK && model.prefs.value.connectionMode == ConnectionMode.VPN) model.startConnection()
        else model.message.value = "未授权 VPN，保持未连接"
    }
    private fun requestConnection() {
        if (model.prefs.value.requested) { model.connect(); return }
        if (!model.canConnect()) return
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            pendingStart = true
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else authorizeAndConnect()
    }
    private fun authorizeAndConnect() {
        if (!model.canConnect()) return
        if (model.prefs.value.connectionMode == ConnectionMode.VPN) {
            val intent = VpnService.prepare(this)
            if (intent != null) { vpnPermission.launch(intent); return }
        }
        model.startConnection()
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val prefs by model.prefs.collectAsStateWithLifecycle()
            val pager = androidx.compose.foundation.pager.rememberPagerState(initialPage = model.selectedPage) { 4 }
            val dark = when (prefs.colors) { ColorMode.SYSTEM -> isSystemInDarkTheme(); ColorMode.DARK -> true; ColorMode.LIGHT -> false }
            SideEffect {
                WindowCompat.getInsetsController(window, window.decorView).apply {
                    isAppearanceLightStatusBars = !dark
                    isAppearanceLightNavigationBars = !dark
                }
            }
            TierNestTheme(prefs) { TierNestScreen(model, pager, ::requestConnection) }
        }
    }
    override fun onStart() { super.onStart(); (application as TierNestApp).uiVisible.value = true; model.reloadPreferences() }
    override fun onStop() { (application as TierNestApp).uiVisible.value = false; super.onStop() }
}
