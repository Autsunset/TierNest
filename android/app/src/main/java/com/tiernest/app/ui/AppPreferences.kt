package com.tiernest.app.ui

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.animation.*
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.tiernest.app.AppModel
import com.tiernest.app.BuildConfig
import com.tiernest.app.data.*

enum class PreferencePage(val title: String) {
    HOME("设置"), APPEARANCE("外观与动效"), SERVICE("运行与省电"), WIFI("家庭网络"), BACKUP("备份与迁移"), ABOUT("关于 TierNest")
}

@Composable fun AppPreferences(model: AppModel, active: Boolean, onOpenConfig: () -> Unit, onImport: () -> Unit, onSubpage: (Boolean) -> Unit) {
    val prefs by model.prefs.collectAsStateWithLifecycle()
    val busy by model.busy.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val appearance = LocalAppearance.current
    val page by model.preferencePage.collectAsStateWithLifecycle()
    LaunchedEffect(page) { onSubpage(page != PreferencePage.HOME) }
    var learn by remember { mutableStateOf(false) }
    var remove by remember { mutableStateOf<HomeNetwork?>(null) }
    var migrationConfirm by remember { mutableStateOf(false) }
    BackHandler(active && page != PreferencePage.HOME) { model.preferencePage.value = PreferencePage.HOME }
    AnimatedContent(page, modifier = Modifier.fillMaxSize(), transitionSpec = {
        if (appearance.reduceMotion) (fadeIn(tween(AppMotion.FADE_MS)) togetherWith fadeOut(tween(AppMotion.FADE_MS))).using(null)
        else {
            val back = targetState == PreferencePage.HOME
            (slideInHorizontally(tween(AppMotion.PAGE_MS, easing = AppMotion.easeOut)) { if (back) -it / 4 else it } + fadeIn(tween(AppMotion.FADE_MS)) togetherWith
                slideOutHorizontally(tween(AppMotion.PAGE_MS, easing = AppMotion.easeOut)) { if (back) it else -it / 4 } + fadeOut(tween(AppMotion.FADE_MS))).using(null)
        }
    }, label = "preference-navigation") { current ->
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.padding(horizontal = 18.dp, vertical = 8.dp)) {
                SettingsHeader(current.title, if (current == PreferencePage.HOME) "PREFERENCES" else "TIERNEST",
                    onBack = if (current == PreferencePage.HOME) null else ({ model.preferencePage.value = PreferencePage.HOME }))
            }
            LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(start = 18.dp, end = 18.dp, bottom = 18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            when (current) {
                PreferencePage.HOME -> {
                    item { GroupLabel("网络与连接") }
                    item { SettingsCard(padding = 4.dp) {
                        PreferenceRow(Icons.Rounded.Tune, "EasyTier 设置", "身份、节点、监听与网络参数", onClick = onOpenConfig)
                        PreferenceRow(Icons.Rounded.PowerSettingsNew, "运行与省电", "手动 / 自动模式与锁屏暂停", if (prefs.automatic) "自动" else "手动") { model.preferencePage.value = PreferencePage.SERVICE }
                        PreferenceRow(Icons.Rounded.Home, "家庭网络", "可信 Wi-Fi 与检测方式", "${prefs.homes.size} 个") { model.preferencePage.value = PreferencePage.WIFI }
                    } }
                    item { GroupLabel("应用") }
                    item { SettingsCard(padding = 4.dp) {
                        PreferenceRow(Icons.Rounded.Palette, "外观与动效", "主题、配色、明暗与减少动态效果", styleName(prefs.theme)) { model.preferencePage.value = PreferencePage.APPEARANCE }
                        PreferenceRow(Icons.Rounded.FolderOpen, "备份与迁移", "导入配置、创建备份、从模块迁移") { model.preferencePage.value = PreferencePage.BACKUP }
                        PreferenceRow(Icons.Rounded.Info, "关于 TierNest", "版本与运行要求", BuildConfig.VERSION_NAME.substringBefore('-')) { model.preferencePage.value = PreferencePage.ABOUT }
                    } }
                    if (prefs.migrationReview.isNotBlank()) item { TextButton(onClick = { model.preferencePage.value = PreferencePage.BACKUP }) { Text("导入配置需要检查，点此继续") } }
                }
                PreferencePage.APPEARANCE -> {
                    item { GroupLabel("界面风格") }
                    item { SettingsCard {
                        ChoiceStrip(listOf("星际", "Material 3", "澎湃"), listOf(ThemeStyle.CONSOLE, ThemeStyle.MATERIAL, ThemeStyle.HYPER).indexOf(prefs.theme),
                            { index -> model.preference { it.copy(theme = listOf(ThemeStyle.CONSOLE, ThemeStyle.MATERIAL, ThemeStyle.HYPER)[index]) } })
                        SmallNote("星际风格参考 interstellar-proxy 的玻璃卡片与控制台布局。")
                    } }
                    item { GroupLabel("明暗与配色") }
                    item { SettingsCard {
                        ChoiceStrip(listOf("跟随系统", "浅色", "深色"), prefs.colors.ordinal, { index -> model.preference { it.copy(colors = ColorMode.entries[index]) } })
                        if (prefs.theme == ThemeStyle.CONSOLE) {
                            Row(Modifier.fillMaxWidth().selectableGroup(), horizontalArrangement = Arrangement.SpaceEvenly) {
                                accents.forEach { accent ->
                                    Column(Modifier.selectable(prefs.accent == accent.id, role = Role.RadioButton,
                                        onClick = { model.preference { it.copy(accent = accent.id) } }).padding(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                                        val color = if (appearance.dark) accent.dark else accent.light
                                        Box(Modifier.size(40.dp).border(if (prefs.accent == accent.id) 2.dp else 0.dp,
                                            if (prefs.accent == accent.id) MaterialTheme.colorScheme.onSurface else androidx.compose.ui.graphics.Color.Transparent, CircleShape)
                                            .padding(5.dp).background(color, CircleShape))
                                        Text(accent.label, style = MaterialTheme.typography.labelSmall)
                                    }
                                }
                            }
                        }
                        if (prefs.theme == ThemeStyle.MATERIAL) PreferenceSwitch("壁纸动态取色", "Android 12 及以上可用", prefs.dynamicColor) { value -> model.preference { it.copy(dynamicColor = value) } }
                    } }
                    item { GroupLabel("动效") }
                    item { SettingsCard {
                        PreferenceSwitch("减少动态效果", "子页改用淡入淡出；同时遵循系统动画设置", prefs.reduceMotion) { value -> model.preference { it.copy(reduceMotion = value) } }
                        SmallNote("左右滑动可切换主页面，点击底部导航直接切换。背景光晕不持续播放动画。")
                    } }
                }
                PreferencePage.SERVICE -> {
                    item { GroupLabel("连接方式") }
                    item { ConnectionModePicker(model) }
                    item { SmallNote(if (prefs.connectionMode == ConnectionMode.VPN) "VPN 模式由系统授权，会占用 VPN 槽位；开启其他 VPN 会替换此连接。" else "Root 模式由 Root 管理器授权，通过独立网卡组网。") }
                    item { GroupLabel("服务模式") }
                    item { SettingsCard {
                        if (prefs.connectionMode == ConnectionMode.ROOT) ChoiceStrip(listOf("手动", "自动"), if (prefs.automatic) 1 else 0, { index ->
                            if (index == 1 && prefs.homes.isEmpty()) {
                                model.message.value = "请先添加并验证一个家庭网络"; model.preferencePage.value = PreferencePage.WIFI
                            } else model.preference { it.copy(automatic = index == 1) }
                        })
                        SmallNote(if (ModePolicy.automatic(prefs.connectionMode, prefs.automatic)) "连接已验证的家庭 Wi-Fi 后暂停手机核心，离开后恢复。" else "通过首页、通知或快捷磁贴控制连接。家庭网关自动识别目前用于 Root 模式。")
                    } }
                    item { GroupLabel("启动与暂停") }
                    item { SettingsCard {
                        PreferenceSwitch("开机恢复连接", "只恢复重启前已开启的连接", prefs.boot) { value -> model.preference { it.copy(boot = value) } }
                        HorizontalDivider()
                        PreferenceSwitch("锁屏时暂停", "会中断当前传输；亮屏后重新连接", prefs.screenSuspend) { value -> model.preference { it.copy(screenSuspend = value) } }
                    } }
                    item { SmallNote("手动点击「断开并停止」始终优先，切换模式与重启不会撤销手动停止。") }
                }
                PreferencePage.WIFI -> {
                    if (prefs.connectionMode == ConnectionMode.VPN) item { SmallNote("VPN 模式不调用 Root 识别网关。已保存的家庭网络偏好保留，切回 Root 模式后使用。") }
                    item { GroupLabel("检测方式") }
                    item { SettingsCard {
                        ChoiceStrip(listOf("Wi-Fi 事件", "定时 HTTP"), prefs.detection.ordinal, { index -> model.preference { it.copy(detection = DetectionMode.entries[index]) } })
                        SmallNote(if (prefs.detection == DetectionMode.EVENT) "匹配网关 IP 与 MAC，不重复发送 HTTP。路由器代理失效但 Wi-Fi 未变时，不会恢复手机核心。"
                            else "经物理 Wi-Fi 验证组网目标；同一网关连续两次失败后恢复。系统休眠可能推迟检查。")
                        if (prefs.detection == DetectionMode.HTTP) {
                            var interval by remember(prefs.interval) { mutableStateOf(prefs.interval.toString()) }
                            EditorField("检测间隔（秒）", interval, { interval = it }, number = true)
                            OutlinedButton(onClick = {
                                val seconds = interval.toIntOrNull()
                                if (seconds == null || seconds <= 0) model.message.value = "请输入正整数秒"
                                else model.preference { it.copy(interval = seconds) }
                            }, modifier = Modifier.fillMaxWidth()) { Text("保存检测间隔") }
                        }
                    } }
                    item { Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Text("已记住的网络 · ${prefs.homes.size}", Modifier.weight(1f), fontWeight = FontWeight.SemiBold)
                        TextButton(onClick = { learn = true }, enabled = !busy && prefs.connectionMode == ConnectionMode.ROOT) { Icon(Icons.Rounded.Add, null, Modifier.size(18.dp)); Text("添加网络") }
                    } }
                    if (prefs.homes.isEmpty()) item { SettingsCard { SmallNote("连接能够代理组网的 Wi-Fi，再验证并记住它。支持保存多个网络。") } }
                    items(prefs.homes, key = { it.id }) { home -> SettingsCard {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(home.gateway, fontWeight = FontWeight.SemiBold)
                                SmallNote("${home.mac}\n验证目标 ${home.target}:${home.port}")
                            }
                            IconButton(onClick = { remove = home }) { Icon(Icons.Rounded.DeleteOutline, "移除网络 ${home.gateway}") }
                        }
                    } }
                }
                PreferencePage.BACKUP -> {
                    item { GroupLabel("配置文件") }
                    item { SettingsCard(padding = 4.dp) {
                        PreferenceRow(Icons.Rounded.UploadFile, "导入 TOML 文件", "先导入草稿，检查后保存", onClick = { if (!busy) onImport() })
                        PreferenceRow(Icons.Rounded.SaveAlt, "备份已保存配置", "保存到 Download/TierNest/backups", onClick = { if (!busy) model.backup() })
                    } }
                    item { GroupLabel("模块迁移") }
                    item { SettingsCard {
                        SmallNote("先复制并校验完整备份，再导入。原模块、参数与历史备份保留，App 保持断开。")
                        OutlinedButton(onClick = model::importModule, enabled = !busy && !prefs.requested && prefs.connectionMode == ConnectionMode.ROOT, modifier = Modifier.fillMaxWidth()) { Text("备份并导入模块配置") }
                        if (prefs.connectionMode == ConnectionMode.VPN) SmallNote("读取模块需要 Root；普通 TOML 文件可以直接导入。")
                        if (prefs.requested) SmallNote("请先断开 App 连接。")
                        if (prefs.migrationReview.isNotBlank()) {
                            SmallNote(prefs.migrationReview)
                            TextButton(onClick = { migrationConfirm = true }) { Text("检查完成，选择 App 运行方式") }
                        }
                    } }
                    if (busy) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
                }
                PreferencePage.ABOUT -> {
                    item { SettingsCard {
                        Text("TierNest ${BuildConfig.VERSION_NAME}", style = MaterialTheme.typography.titleLarge)
                        SmallNote("EasyTier 2.6.4 · Root / VPN 双模式 · arm64 与 x86_64")
                        SmallNote("VPN 模式只需系统授权。Root 模式需原生 arm64、Root 权限、TUN 和 iptables。")
                    } }
                    item { SettingsCard {
                        Text("路由与兼容", fontWeight = FontWeight.SemiBold)
                        SmallNote("只接管组网 IPv4 目标。Root 模式让出 VPN 槽位，VPN 模式使用系统槽位；厂商网络策略仍可能影响连接。")
                        SmallNote("当前不支持热点转发、出口节点和 IPv6 虚拟路由。升级保留原始配置；不兼容的旧设置需要明确选择。")
                    } }
                    item { SettingsCard(padding = 4.dp) {
                        PreferenceRow(Icons.Rounded.Code, "TierNest 源码", "源代码、版本与问题反馈 · LGPL-3.0") { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/Autsunset/TierNest"))) }
                        PreferenceRow(Icons.Rounded.Code, "EasyTier", "上游源码 · LGPL-3.0") { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/EasyTier/EasyTier/tree/v2.6.4"))) }
                        PreferenceRow(Icons.Rounded.Palette, "视觉参考", "interstellar-proxy · MIT") { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/zn0wii/interstellar-proxy"))) }
                        PreferenceRow(Icons.Rounded.Palette, "澎湃组件", "Miuix 0.6.1 · Apache-2.0") { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/compose-miuix-ui/miuix"))) }
                    } }
                }
            }
            }
        }
    }
    if (learn) {
        var target by remember { mutableStateOf("") }
        var port by remember { mutableStateOf("80") }
        val homeError by model.homeError.collectAsStateWithLifecycle()
        AlertDialog(onDismissRequest = { if (!busy) learn = false }, title = { Text("验证当前 Wi-Fi") }, text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                SmallNote("填写经当前路由器可访问的组网 HTTP 地址。")
                EditorField("虚拟 IPv4", target, { target = it }, "例如 10.77.0.1")
                EditorField("HTTP 端口", port, { port = it }, number = true)
                if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
                if (homeError.isNotEmpty()) SmallNote(homeError, error = true)
            }
        }, confirmButton = { TextButton(onClick = { model.learnHome(target, port) { learn = false } }, enabled = !busy) { Text(if (busy) "验证中…" else "验证并保存") } },
            dismissButton = { TextButton(onClick = { learn = false }, enabled = !busy) { Text("取消") } })
    }
    remove?.let { home -> AlertDialog(onDismissRequest = { remove = null }, title = { Text("移除此家庭网络？") },
        text = { Text("移除后不再对该网络自动待机。移除最后一个网络会回到手动模式。") },
        confirmButton = { TextButton(onClick = {
            model.preference { old -> val homes = old.homes.filterNot { it.id == home.id }; old.copy(homes = homes, automatic = old.automatic && homes.isNotEmpty()) }
            remove = null
        }) { Text("移除") } }, dismissButton = { TextButton(onClick = { remove = null }) { Text("取消") } }) }
    if (migrationConfirm) AlertDialog(onDismissRequest = { migrationConfirm = false }, title = { Text("使用 App 运行方式？") },
        text = { Text("确认已停用旧模块，并检查 TOML 与命令参数。App 使用独立目标路由，暂不启用热点转发；原文件和备份保留。此操作不会启动连接。") },
        confirmButton = { TextButton(onClick = { model.preference { it.copy(migrationReview = "") }; migrationConfirm = false }) { Text("确认选择") } },
        dismissButton = { TextButton(onClick = { migrationConfirm = false }) { Text("继续检查") } })
}

fun styleName(style: ThemeStyle): String = when (style) { ThemeStyle.CONSOLE -> "星际"; ThemeStyle.MATERIAL -> "Material 3"; ThemeStyle.HYPER -> "澎湃" }
