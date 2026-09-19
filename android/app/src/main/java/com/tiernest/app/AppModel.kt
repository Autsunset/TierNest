package com.tiernest.app

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.tiernest.app.data.*
import com.tiernest.app.service.ConnectionService
import com.tiernest.app.service.HomeDetector
import com.tiernest.app.engine.NativeVpn
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File

class AppModel(application: Application) : AndroidViewModel(application) {
    private val app = application as TierNestApp
    val dashboard = app.dashboard
    val prefs = MutableStateFlow(app.store.load())
    val config = MutableStateFlow(app.store.readConfig())
    val editor = MutableStateFlow(ConfigDraft.load(config.value))
    val editorError = MutableStateFlow("")
    val homeError = MutableStateFlow("")
    val preferencePage = MutableStateFlow(com.tiernest.app.ui.PreferencePage.HOME)
    var selectedPage = 0
    val busy = MutableStateFlow(false)
    val message = MutableStateFlow("")
    private val writes = Mutex()
    private val preferenceWrites = Mutex()
    private var preferenceRevision = 0L
    init { viewModelScope.launch { app.store.requested.collect { requested -> prefs.update { it.copy(requested = requested) } } } }

    fun reloadPreferences() { prefs.update { it.copy(requested = app.store.load().requested) } }
    fun refreshConnection() { ConnectionService.refreshFromUserAction(app); reloadPreferences() }
    fun preference(change: (Preferences) -> Preferences) {
        val revision = ++preferenceRevision
        prefs.value = change(prefs.value) // Immediate visual feedback; fsync stays off the UI thread.
        viewModelScope.launch {
            try {
                // Acquire on the main dispatcher before dispatching IO so rapid
                // selections are persisted in the same order they were made.
                val (old, next) = preferenceWrites.withLock { withContext(Dispatchers.IO) {
                    val old = app.store.load()
                    old to app.store.update(change)
                } }
                if (revision == preferenceRevision) prefs.value = next.copy(requested = app.store.requested.value)
                if (old.screenSuspend != next.screenSuspend || old.automatic != next.automatic || old.homes != next.homes ||
                    old.detection != next.detection || old.interval != next.interval) ConnectionService.settingsChanged(app)
            } catch (error: Exception) {
                if (revision == preferenceRevision) prefs.value = app.store.load()
                message.value = error.message ?: "设置保存失败"
            }
        }
    }

    fun connect() {
        if (busy.value) { message.value = "请等待当前操作完成"; return }
        val requested = app.store.load().requested
        if (!requested && !canConnect()) return
        ConnectionService.request(app, !requested)
        reloadPreferences()
    }
    fun canConnect(): Boolean = runCatching {
            check(!busy.value) { "请等待当前操作完成" }
            check(prefs.value.migrationReview.isEmpty()) { "请先在设置中检查导入配置" }
            ConfigCodec.effective(config.value, app.store.load().connectionMode)
        }.onFailure { message.value = it.message ?: "请先配置网络" }.isSuccess
    fun startConnection() {
        if (!app.store.load().requested && canConnect()) ConnectionService.request(app, true)
        reloadPreferences()
    }

    fun chooseConnectionMode(mode: ConnectionMode) = task {
        withContext(Dispatchers.Main) { ConnectionService.request(app, false) }
        prefs.value = app.store.update { it.copy(connectionMode = mode, requested = false) }
        message.value = "已选择${mode.label}，点击连接后生效"
    }

    private suspend fun validateConfiguration(text: String) {
        val mode = app.store.load().connectionMode
        if (mode == ConnectionMode.ROOT) app.engine.validate(text)
        else withContext(Dispatchers.IO) { NativeVpn.validate(ConfigCodec.effective(text, mode)) }
    }

    private suspend fun backupConfiguration(text: String): String =
        if (app.store.load().connectionMode == ConnectionMode.ROOT) app.engine.backup(text) else app.backups.create(text)

    fun task(block: suspend () -> Unit) {
        if (busy.value) return
        busy.value = true
        viewModelScope.launch {
            try { withContext(Dispatchers.IO) { writes.withLock { block() } } }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) { message.value = error.message ?: "操作失败" }
            finally { busy.value = false }
        }
    }

    fun editForm(change: (NetworkForm) -> NetworkForm) { editor.update { it.edit(change) }; editorError.value = "" }
    fun editSource(text: String) { editor.update { it.editText(text) }; editorError.value = "" }
    fun renameEntry(group: String, old: String, replacement: String, index: Int): Boolean = runCatching {
        editor.update { it.renameEntry(group, old, replacement, index) }; editorError.value = ""
    }.onFailure { editorError.value = it.message ?: "修改失败" }.isSuccess
    fun selectConfigTab(tab: ConfigTab) {
        runCatching { editor.value.select(tab) }.onSuccess { editor.value = it; editorError.value = "" }
            .onFailure { editorError.value = it.message ?: "无法切换配置视图" }
    }
    fun reloadConfig() {
        config.value = app.store.readConfig()
        editor.value = ConfigDraft.load(config.value, editor.value.tab)
        editorError.value = ""
    }
    fun importDraft(text: String) {
        ConfigCodec.parse(text)
        editor.value = ConfigDraft.load(text).copy(savedText = config.value, revision = editor.value.revision + 1)
        editorError.value = ""; message.value = "已导入到草稿，保存后生效"
    }
    fun validateDraft() = task {
        try { validateConfiguration(editor.value.payload()); editorError.value = ""; message.value = "配置验证通过" }
        catch (error: Exception) { editorError.value = error.message ?: "配置校验失败"; throw error }
    }
    fun saveDraft(reconnect: Boolean = false) {
        val snapshot = editor.value
        val text = runCatching { snapshot.payload() }.onFailure { editorError.value = it.message.orEmpty() }.getOrNull() ?: return
        task { save(text, snapshot.revision, reconnect) }
    }
    private suspend fun save(text: String, revision: Long, reconnect: Boolean) {
        try {
        validateConfiguration(text)
        val old = app.store.readConfig()
        if (old != ConfigCodec.template && old != text) backupConfiguration(old)
        app.store.writeConfig(text)
        config.value = text
        editor.update { it.acknowledge(text, revision) }
        editorError.value = ""
        message.value = "配置已保存${if (app.store.load().requested) "，重新连接后生效" else ""}"
        if (reconnect) withContext(Dispatchers.Main) {
            ConnectionService.reconnect(app)
            message.value = "配置已保存，按当前运行方式重新应用"
        }
        } catch (error: Exception) { editorError.value = error.message ?: "保存失败"; throw error }
    }

    fun backup() = task { message.value = "备份已保存：${backupConfiguration(app.store.readConfig())}" }

    fun learnHome(target: String, port: String, expectedId: String? = null, onSaved: () -> Unit = {}) = task {
        homeError.value = ""
        try {
        check(app.store.load().connectionMode == ConnectionMode.ROOT) { "家庭网关识别目前用于 Root 模式" }
        val record = HomeDetector(app).learn(target.trim(), port.toIntOrNull() ?: error("请输入有效端口"))
        check(expectedId == null || expectedId == record.id) { "当前 Wi-Fi 与该记录不同，请先连接此家庭网络" }
        prefs.value = app.store.update { it.copy(homes = it.homes.filterNot { h -> h.id == record.id } + record) }
        message.value = "已验证并记住当前 Wi-Fi"
        withContext(Dispatchers.Main) { ConnectionService.settingsChanged(app); onSaved() }
        } catch (error: Exception) { homeError.value = error.message ?: "验证失败"; throw error }
    }

    fun importModule() = task {
        check(app.store.load().connectionMode == ConnectionMode.ROOT) { "读取模块配置需要先选择 Root 模式" }
        check(!app.store.load().requested) { "请先断开 App 连接" }
        val backup = app.engine.importModule()
        val source = File(app.engine.stage, "import")
        val file = File(source, "config/config.toml")
        check(file.length() <= ConfigCodec.MAX_BYTES) { "模块配置超过大小限制" }
        val text = file.readText()
        ConfigCodec.parse(text)
        val old = app.store.readConfig()
        if (old != ConfigCodec.template) app.engine.backup(old)
        // Keep the complete snapshot independent of future engine asset updates.
        val archive = File(app.filesDir, "legacy/${System.currentTimeMillis()}")
        check(source.copyRecursively(archive)) { "本地迁移快照保存失败" }
        val configDir = File(source, "config")
        fun original(name: String) = File(configDir, name).takeIf { it.isFile }?.readText().orEmpty()
        val detection = LegacyImport.fields(original("home-detection.conf"))
        val hasArgs = File(configDir, "command_args").length() > 0
        val review = buildString {
            append("已备份原 TOML、参数、路由与热点偏好、家庭网络和停止状态。原模块未停用。\n")
            append("App 使用独立的 IPv4 目标路由、tiernest0 和本机 RPC；原路由策略与热点功能不会自动转换。\n")
            if (hasArgs) append("原模块使用 command_args：参数原文已保留，请先在配置页手动转换成等效 TOML，再确认。\n")
            append("请先在原模块中停止服务，再到 Root 管理器停用模块。确认后只改变 App 的运行选择，备份原件保留。")
        }
        app.store.writeConfig(text)
        prefs.value = app.store.update { it.copy(requested = false,
            automatic = original("service-mode.state").trim() == "auto",
            detection = if (detection["mode"] == "event") DetectionMode.EVENT else DetectionMode.HTTP,
            interval = detection["interval"]?.toIntOrNull()?.takeIf { n -> n > 0 } ?: 30,
            homes = LegacyImport.homes(original("home-network.conf")), migrationReview = review) }
        config.value = text
        editor.value = ConfigDraft.load(text)
        message.value = "已导入并保持断开。备份：$backup；请在设置中检查迁移说明。"
    }
}

object LegacyImport {
    fun fields(text: String) = text.lines().filter { '=' in it && !it.trimStart().startsWith('#') }
        .associate { it.substringBefore('=').trim() to it.substringAfter('=').trim() }

    fun homes(text: String): List<HomeNetwork> {
        val rows = text.lines().filter { it.startsWith("network=") }.map { it.substringAfter('=') }
        val values = fields(text)
        val records = rows.ifEmpty {
            if (listOf("interface", "gateway", "mac", "target", "port").all { it in values })
                listOf(listOf("interface", "gateway", "mac", "target", "port").joinToString("|") { values[it].orEmpty() })
            else emptyList()
        }
        return records.mapNotNull {
            val p = it.split('|')
            if (p.size != 5 || !p[0].matches(Regex("wlan[0-9]+")) || RoutePlanner.cidr(p[1]) == null ||
                !p[2].matches(Regex("([0-9a-f]{2}:){5}[0-9a-f]{2}")) || RoutePlanner.cidr(p[3]) == null ||
                (p[4].toIntOrNull() ?: 0) !in 1..65535) null
            else HomeNetwork(p[0], p[1], p[2], p[3], p[4].toInt())
        }
    }
}
