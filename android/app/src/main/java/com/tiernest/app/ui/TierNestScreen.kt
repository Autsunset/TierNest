package com.tiernest.app.ui

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.tiernest.app.*
import com.tiernest.app.data.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.max
import kotlinx.coroutines.launch

@Composable fun TierNestScreen(model: AppModel, pager: androidx.compose.foundation.pager.PagerState, onConnect: () -> Unit) {
    val prefs by model.prefs.collectAsStateWithLifecycle()
    val message by model.message.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }
    val app = LocalContext.current.applicationContext as TierNestApp
    var settingsOpen by remember { mutableStateOf(false) }
    var jump by remember { mutableStateOf<kotlinx.coroutines.Job?>(null) }
    fun navigate(index: Int) {
        jump?.cancel()
        jump = scope.launch { pager.scrollToPage(index) }
    }
    val importFile = rememberConfigurationImport(model) { navigate(2) }
    LaunchedEffect(message) { if (message.isNotBlank()) { snackbar.showSnackbar(message); if (model.message.value == message) model.message.value = "" } }
    LaunchedEffect(pager.settledPage) { model.selectedPage = pager.settledPage; app.uiDataVisible.value = pager.settledPage < 2 }
    DisposableEffect(app) { onDispose { app.uiDataVisible.value = false } }
    androidx.activity.compose.BackHandler(pager.currentPage != 0 && !(pager.currentPage == 3 && settingsOpen)) { navigate(0) }
    AmbientBackground(Modifier.fillMaxSize()) {
        Scaffold(containerColor = Color.Transparent, contentColor = MaterialTheme.colorScheme.onSurface,
            snackbarHost = { SnackbarHost(snackbar) },
            bottomBar = { PageDock(pager) { navigate(it) } }) { padding ->
            androidx.compose.foundation.pager.HorizontalPager(
                state = pager,
                beyondViewportPageCount = 1,
                userScrollEnabled = !(pager.currentPage == 3 && settingsOpen),
                modifier = Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding).imePadding(),
                key = { it },
            ) { page ->
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
                    Box(Modifier.fillMaxHeight().widthIn(max = 840.dp).fillMaxWidth()) {
                        val active = page == pager.settledPage
                        when (page) {
                            0 -> LiveDashboard(model, active) { state -> Overview(model, state, prefs, onConnect, { navigate(2) }) }
                            1 -> LiveDashboard(model, active) { state -> PeersScreen(state) }
                            2 -> NetworkConfiguration(model, importFile)
                            else -> AppPreferences(model, active, { navigate(2) }, importFile) { settingsOpen = it }
                        }
                    }
                }
            }
        }
    }
}

@Composable private fun LiveDashboard(model: AppModel, active: Boolean, content: @Composable (Dashboard) -> Unit) {
    val state by produceState(Dashboard(), model, active) {
        value = model.dashboard.value
        if (active) model.dashboard.collect { value = it }
    }
    content(state)
}

@Composable private fun PageTitle(title: String, subtitle: String) {
    Column(Modifier.padding(top = 12.dp, bottom = 8.dp)) {
        Text(title, style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
        Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 6.dp))
    }
}

@Composable private fun Panel(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    SettingsCard(modifier, padding = 18.dp, content = content)
}

@Composable private fun Overview(model: AppModel, state: Dashboard, prefs: Preferences, onConnect: () -> Unit, onConfig: () -> Unit) {
    val clock = remember { java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault()) }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item { SettingsHeader("TierNest", "YOUR PRIVATE NETWORK") }
        item { ConnectionModePicker(model) }
        item {
            Surface(shape = MaterialTheme.shapes.extraLarge,
                color = if (state.active) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainer) {
                Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Surface(shape = CircleShape, color = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)) {
                        Icon(if (state.active) Icons.Rounded.Hub else Icons.Rounded.PowerSettingsNew, null,
                            tint = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(16.dp).size(32.dp))
                    }
                    Spacer(Modifier.height(14.dp))
                    Text(state.phase, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.SemiBold)
                    Text(state.detail, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 8.dp, bottom = 16.dp))
                    if (state.busy) LinearProgressIndicator(Modifier.fillMaxWidth().padding(bottom = 16.dp))
                    Button(onClick = onConnect, modifier = Modifier.fillMaxWidth().height(54.dp),
                        shape = if (prefs.theme == ThemeStyle.HYPER) MaterialTheme.shapes.medium else CircleShape) {
                        Icon(if (prefs.requested) Icons.Rounded.Stop else Icons.Rounded.PlayArrow, null)
                        Spacer(Modifier.width(8.dp)); Text(when {
                            prefs.requested -> "断开并停止"
                            state.error.isNotBlank() -> "重新连接"
                            else -> "连接网络"
                        }, fontSize = 16.sp)
                    }
                }
            }
        }
        if (state.error.isNotBlank()) item {
            Surface(color = MaterialTheme.colorScheme.errorContainer, shape = MaterialTheme.shapes.medium) {
                Text(state.error, Modifier.padding(16.dp), color = MaterialTheme.colorScheme.onErrorContainer)
            }
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Panel(Modifier.weight(1f)) { Text("虚拟地址", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(state.cidr.ifBlank { "未分配" }, fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.titleMedium) }
                Panel(Modifier.weight(1f)) { Text("可见节点", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(if (state.active) state.peers.count { it.hops != 0 }.toString() else "—", fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleLarge) }
            }
        }
        item { Panel {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Column { Text("↓ 接收", color = MaterialTheme.colorScheme.primary); Text(rate(state.rxRate), fontWeight = FontWeight.SemiBold) }
                Column { Text("↑ 发送", color = MaterialTheme.colorScheme.tertiary); Text(rate(state.txRate), fontWeight = FontWeight.SemiBold) }
            }
            TrafficChart(state.samples)
            Text("累计接收 ${bytes(state.rxTotal)} · 发送 ${bytes(state.txTotal)}", style = MaterialTheme.typography.labelMedium)
            Text("仅在界面可见时连续采样", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        } }
        item { Panel {
            LabelRow(if (prefs.connectionMode == ConnectionMode.ROOT) Icons.Rounded.Shield else Icons.Rounded.VpnKey,
                prefs.connectionMode.label, if (prefs.connectionMode == ConnectionMode.ROOT) "不占用 Android VPN 槽位" else "系统 VPN 分流 · 仅接管组网目标")
            HorizontalDivider()
            DetailLine("连接时长", if (state.active) duration(state.uptimeSeconds) else "—")
            DetailLine("当前网络", state.underlay.ifBlank { "连接后获取" })
            DetailLine("组网路由", if (state.active) "${state.routeCount} 个目标" else "—")
            if (state.table.isNotBlank()) DetailLine("策略路由", "表 ${state.table} · 优先级 ${state.priority}")
            if (prefs.connectionMode == ConnectionMode.ROOT) DetailLine("系统 VPN", if (state.vpn) "已检测到" else "未检测到")
            if (state.updatedAt > 0) DetailLine("数据更新", clock.format(java.util.Date(state.updatedAt)))
            TextButton(onClick = onConfig) { Text("管理组网配置"); Icon(Icons.Rounded.ChevronRight, null) }
        } }
        if (state.excluded.isNotEmpty()) item { Panel {
            Text("未接管的目标", fontWeight = FontWeight.SemiBold)
            Text("下列路由与本地网络重叠，或超出首版 IPv4 分流范围：\n${state.excluded.joinToString("、")}")
        } }
    }
}

@Composable private fun LabelRow(icon: ImageVector, title: String, subtitle: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Icon(icon, null, tint = MaterialTheme.colorScheme.primary)
        Column { Text(title, fontWeight = FontWeight.Medium); Text(subtitle, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall) }
    }
}

private fun rate(value: Float): String = when {
    value >= 1024 * 1024 -> "%.1f MiB/s".format(value / (1024 * 1024))
    value >= 1024 -> "%.1f KiB/s".format(value / 1024)
    else -> "%.0f B/s".format(value)
}

@Composable private fun TrafficChart(samples: List<Pair<Float, Float>>) {
    val primary = MaterialTheme.colorScheme.primary
    val secondary = MaterialTheme.colorScheme.tertiary
    val grid = MaterialTheme.colorScheme.outlineVariant
    Canvas(Modifier.fillMaxWidth().height(100.dp).semantics { contentDescription = "最近的接收与发送速率曲线" }) {
        for (i in 1..3) drawLine(grid.copy(alpha = 0.45f), Offset(0f, size.height * i / 4), Offset(size.width, size.height * i / 4), 1f)
        if (samples.size < 2) return@Canvas
        val peak = max(1024f, samples.maxOf { max(it.first, it.second) }) * 1.1f
        listOf(true to primary, false to secondary).forEach { (rx, color) ->
            val path = Path()
            samples.forEachIndexed { index, sample ->
                val x = index.toFloat() / (samples.size - 1) * size.width
                val y = size.height - (if (rx) sample.first else sample.second) / peak * size.height
                if (index == 0) path.moveTo(x, y) else path.lineTo(x, y)
            }
            drawPath(path, color, style = Stroke(2.dp.toPx(), cap = StrokeCap.Round))
        }
    }
}


@Composable internal fun DetailLine(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(label, modifier = Modifier.weight(0.8f), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        androidx.compose.foundation.text.selection.SelectionContainer(Modifier.weight(1.2f)) {
            Text(value, modifier = Modifier.fillMaxWidth(), style = MaterialTheme.typography.bodyMedium, textAlign = androidx.compose.ui.text.style.TextAlign.End)
        }
    }
}

internal fun bytes(value: Long): String = when {
    value >= 1024L * 1024 * 1024 -> "%.2f GiB".format(value / (1024.0 * 1024 * 1024))
    value >= 1024L * 1024 -> "%.1f MiB".format(value / (1024.0 * 1024))
    value >= 1024 -> "%.1f KiB".format(value / 1024.0)
    else -> "$value B"
}
private fun duration(seconds: Long) = "%02d:%02d:%02d".format(seconds / 3600, seconds / 60 % 60, seconds % 60)
