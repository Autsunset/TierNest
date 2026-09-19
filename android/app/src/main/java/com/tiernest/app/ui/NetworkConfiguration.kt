package com.tiernest.app.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.tiernest.app.AppModel
import com.tiernest.app.data.*

private enum class EndpointKind(val title: String) { PEER("对等节点"), LISTENER("监听地址"), SUBNET("共享子网") }
private data class EndpointEdit(val kind: EndpointKind, val index: Int = -1, val value: String = "")

@OptIn(ExperimentalLayoutApi::class)
@Composable fun NetworkConfiguration(model: AppModel, onImport: () -> Unit) {
    val draft by model.editor.collectAsStateWithLifecycle()
    val busy by model.busy.collectAsStateWithLifecycle()
    val error by model.editorError.collectAsStateWithLifecycle()
    val prefs by model.prefs.collectAsStateWithLifecycle()
    var menu by remember { mutableStateOf(false) }
    var reload by remember { mutableStateOf(false) }
    var edit by remember { mutableStateOf<EndpointEdit?>(null) }
    val form = draft.form
    val scrollStates = ConfigTab.entries.map { rememberLazyListState() }
    fun values(kind: EndpointKind) = when (kind) {
        EndpointKind.PEER -> form.peers.lines().filter { it.isNotBlank() }
        EndpointKind.LISTENER -> form.listeners
        EndpointKind.SUBNET -> form.subnets.lines().filter { it.isNotBlank() }
    }
    fun setValues(kind: EndpointKind, list: List<String>) = model.editForm { when (kind) {
        EndpointKind.PEER -> it.copy(peers = list.joinToString("\n"))
        EndpointKind.LISTENER -> it.copy(listeners = list)
        EndpointKind.SUBNET -> it.copy(subnets = list.joinToString("\n"))
    } }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.padding(horizontal = 18.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SettingsHeader("EasyTier 设置", "NETWORK") {
                Box {
                    IconButton(onClick = { menu = true }) { Icon(Icons.Rounded.MoreVert, "配置操作") }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(text = { Text("验证配置") }, onClick = { menu = false; model.validateDraft() }, enabled = !busy)
                        DropdownMenuItem(text = { Text("导入 TOML 文件") }, onClick = { menu = false; onImport() }, enabled = !busy)
                        DropdownMenuItem(text = { Text("备份已保存配置") }, onClick = { menu = false; model.backup() }, enabled = !busy)
                        DropdownMenuItem(text = { Text("重新加载") }, onClick = { menu = false; if (draft.dirty) reload = true else model.reloadConfig() }, enabled = !busy)
                    }
                }
            }
            ChoiceStrip(ConfigTab.entries.map { it.label }, draft.tab.ordinal, { model.selectConfigTab(ConfigTab.entries[it]) })
        }
        if (error.isNotBlank()) Surface(color = MaterialTheme.colorScheme.errorContainer) {
            Row(Modifier.padding(start = 18.dp, top = 8.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(error, Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onErrorContainer)
                IconButton(onClick = { model.editorError.value = "" }) { Icon(Icons.Rounded.Close, "收起错误") }
            }
        }
        LazyColumn(Modifier.weight(1f), state = scrollStates[draft.tab.ordinal], contentPadding = PaddingValues(start = 18.dp, end = 18.dp, top = 8.dp, bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            when (draft.tab) {
                ConfigTab.IDENTITY -> {
                    item { GroupLabel("网络身份") }
                    item { SettingsCard {
                        EditorField("组网名称", form.name, { model.editForm { f -> f.copy(name = it) } }, "所有设备填写相同名称")
                        var visible by remember { mutableStateOf(false) }
                        OutlinedTextField(form.secret, { model.editForm { f -> f.copy(secret = it) } }, modifier = Modifier.fillMaxWidth(),
                            label = { Text("组网密钥") }, singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false),
                            visualTransformation = if (visible) VisualTransformation.None else PasswordVisualTransformation(),
                            trailingIcon = { IconButton(onClick = { visible = !visible }) { Icon(if (visible) Icons.Rounded.VisibilityOff else Icons.Rounded.Visibility, if (visible) "隐藏密钥" else "显示密钥") } })
                        SmallNote("与要连接的设备使用相同的组网名称和密钥。")
                    } }
                    item { GroupLabel("本机与地址") }
                    item { SettingsCard {
                        val systemName by model.deviceName.collectAsStateWithLifecycle()
                        EditorField("设备名称", form.hostname, { model.editForm { f -> f.copy(hostname = it) } }, "自动：$systemName")
                        SmallNote(if (form.hostname.isBlank()) "下次连接自动使用：$systemName" else
                            "已使用配置中的名称；清空后自动使用：$systemName")
                        EditorField("实例名称", form.instanceName, { model.editForm { f -> f.copy(instanceName = it) } })
                        HorizontalDivider()
                        PreferenceSwitch("自动分配 IPv4", "开启 DHCP；已有静态地址会保留在草稿中", form.dhcp) { model.editForm { f -> f.copy(dhcp = it) } }
                        if (!form.dhcp) EditorField("虚拟 IPv4 / CIDR", form.ipv4, { model.editForm { f -> f.copy(ipv4 = it) } }, "例如 10.77.0.2/24", mono = true)
                    } }
                    item { TextButton(onClick = { model.selectConfigTab(ConfigTab.ENDPOINTS) }) { Text("下一步：添加对等节点"); Icon(Icons.Rounded.ArrowForward, null) } }
                }
                ConfigTab.ENDPOINTS -> {
                    for (kind in EndpointKind.entries) {
                        val list = values(kind)
                        item(key = "header-$kind") {
                            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                Text("${kind.title} · ${list.size}", Modifier.weight(1f), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                                TextButton(onClick = { edit = EndpointEdit(kind) }) {
                                    Icon(Icons.Rounded.Add, null, Modifier.size(18.dp)); Text("添加${if (kind == EndpointKind.PEER) "节点" else if (kind == EndpointKind.LISTENER) "监听" else "子网"}")
                                }
                            }
                        }
                        if (list.isEmpty()) item(key = "empty-$kind") { SettingsCard { SmallNote(when (kind) {
                            EndpointKind.PEER -> "添加服务器或已在线设备的连接地址。"
                            EndpointKind.LISTENER -> "添加监听后，其他节点才能主动连接本机。"
                            EndpointKind.SUBNET -> "需要通过本机共享局域网时添加，普通客户端可留空。"
                        }) } }
                        itemsIndexed(list, key = { index, _ -> "$kind-$index" }) { index, value ->
                            SettingsCard(padding = 10.dp) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(if (kind == EndpointKind.SUBNET) Icons.Rounded.Lan else Icons.Rounded.Link, null,
                                        tint = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(8.dp).size(20.dp))
                                    Text(value, Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace)
                                    IconButton(onClick = { edit = EndpointEdit(kind, index, value) }) { Icon(Icons.Rounded.Edit, "编辑${kind.title} ${index + 1}", Modifier.size(18.dp)) }
                                    IconButton(onClick = { setValues(kind, list.filterIndexed { i, _ -> i != index }) }) { Icon(Icons.Rounded.Close, "删除${kind.title} ${index + 1}", Modifier.size(18.dp)) }
                                }
                            }
                        }
                        if (kind == EndpointKind.LISTENER) item(key = "presets") {
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                listOf("TCP" to "tcp://0.0.0.0:11010", "UDP" to "udp://0.0.0.0:11010", "WG" to "wg://0.0.0.0:11011", "WSS" to "wss://0.0.0.0:11012").forEach { (label, uri) ->
                                    AssistChip(onClick = { if (uri !in list) setValues(kind, list + uri) else model.message.value = "该监听已存在" },
                                        label = { Text("+ $label ${uri.substringAfterLast(':')}") })
                                }
                            }
                        }
                    }
                }
                ConfigTab.FEATURES -> {
                    item { GroupLabel("网卡与传输") }
                    item { SettingsCard {
                        EditorField("MTU", form.mtu, { model.editForm { f -> f.copy(mtu = it) } }, "576–9000，默认 1380", number = true)
                        SmallNote(if (prefs.connectionMode == ConnectionMode.ROOT) "Root 模式固定使用 tiernest0 和本机 RPC；原始 TOML 独立保留。"
                            else "VPN 网卡由 Android 创建，内核在 App 内运行，不开放本机 RPC 端口。")
                    } }
                    val options = listOf(
                        Triple("enable_encryption", "数据加密", "保护节点之间的组网数据"),
                        Triple("enable_ipv6", "IPv6 传输", "允许通过 IPv6 连接节点和打洞"),
                        Triple("latency_first", "延迟优先", "优先选择时延较低的传输路径"),
                        Triple("disable_p2p", "纯中继模式", "禁用 P2P 直连，使用中继路径"),
                        Triple("bind_device", "绑定物理网卡", "将传输套接字绑定到出口设备"),
                        Triple("private_mode", "私有模式", "限制其他网络通过本机中继"),
                        Triple("disable_udp_hole_punching", "禁用 UDP 打洞", "不尝试 UDP NAT 穿透"),
                        Triple("disable_tcp_hole_punching", "禁用 TCP 打洞", "不尝试 TCP NAT 穿透"),
                        Triple("enable_kcp_proxy", "KCP TCP 代理", "实验性传输选项，按需启用"),
                        Triple("use_smoltcp", "用户态 TCP 栈", "代理 / KCP 路径的兼容选项"),
                    )
                    itemsIndexed(options, key = { _, item -> item.first }) { _, (key, title, hint) -> SettingsCard(padding = 12.dp) {
                        if (key == "bind_device" && prefs.connectionMode == ConnectionMode.VPN) SmallNote("VPN 模式由 Android 管理出口；Root 的绑定网卡偏好保留。")
                        else PreferenceSwitch(title, hint, form.features.getValue(key)) { value -> model.editForm { it.copy(features = it.features + (key to value)) } }
                    } }
                    if (form.features["enable_kcp_proxy"] == true) item { SettingsCard {
                        SmallNote(if (form.features["use_smoltcp"] == true) "已启用 KCP 与用户态 TCP 栈。遇到 TCP 访问异常时，可先关闭 KCP 排查。"
                            else "KCP 未搭配用户态 TCP 栈；部分定制内核可能出现 Ping 正常、TCP 超时。", error = form.features["use_smoltcp"] != true)
                    } }
                }
                ConfigTab.SOURCE -> {
                    item { SmallNote("完整 TOML · ${draft.document.lineSequence().count()} 行。切回可视化设置时会同步字段。") }
                    item { OutlinedTextField(draft.document, model::editSource, Modifier.fillMaxWidth().heightIn(min = 400.dp),
                        label = { Text("TOML 源码") }, textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace)) }
                }
            }
        }
        Surface(color = MaterialTheme.colorScheme.surface) {
            Column(Modifier.padding(horizontal = 18.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Column(Modifier.weight(1f)) {
                        Text(if (draft.dirty) "有未保存的修改" else "与已保存配置一致", style = MaterialTheme.typography.labelMedium,
                            color = if (draft.dirty) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                        if (prefs.requested) TextButton(onClick = { model.saveDraft(reconnect = true) }, enabled = !busy) { Text("保存并应用") }
                    }
                    Button(onClick = { model.saveDraft() }, enabled = !busy && draft.dirty) {
                        Icon(Icons.Rounded.Save, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text("保存配置")
                    }
                }
            }
        }
    }
    if (reload) AlertDialog(onDismissRequest = { reload = false }, title = { Text("重新加载配置？") }, text = { Text("未保存的修改将被丢弃。") },
        confirmButton = { TextButton(onClick = { model.reloadConfig(); reload = false }) { Text("重新加载") } },
        dismissButton = { TextButton(onClick = { reload = false }) { Text("取消") } })
    edit?.let { current ->
        var input by remember(current) { mutableStateOf(current.value) }
        var fieldError by remember(current) { mutableStateOf("") }
        AlertDialog(onDismissRequest = { edit = null }, title = { Text("${if (current.index < 0) "添加" else "编辑"}${current.kind.title}") },
            text = { Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(input, { input = it; fieldError = "" }, label = { Text(if (current.kind == EndpointKind.SUBNET) "IPv4 / CIDR" else "完整连接地址") },
                    keyboardOptions = KeyboardOptions(keyboardType = if (current.kind == EndpointKind.SUBNET) KeyboardType.Ascii else KeyboardType.Uri, autoCorrectEnabled = false),
                    placeholder = { Text(if (current.kind == EndpointKind.SUBNET) "192.0.2.0/24" else "tcp://relay.example.com:11010") },
                    isError = fieldError.isNotEmpty(), supportingText = { if (fieldError.isNotEmpty()) Text(fieldError) }, modifier = Modifier.fillMaxWidth())
                if (current.kind != EndpointKind.SUBNET) SmallNote("支持 tcp、udp、wg、ws 和 wss；可直接粘贴连接地址。")
            } }, confirmButton = { TextButton(onClick = {
                val value = input.trim()
                val entries = values(current.kind).toMutableList()
                fieldError = when {
                    value.isBlank() -> "请输入地址"
                    entries.withIndex().any { it.index != current.index && it.value == value } -> "该地址已存在"
                    current.kind == EndpointKind.SUBNET && RoutePlanner.cidr(value) == null -> "请输入有效的 IPv4 / CIDR"
                    current.kind != EndpointKind.SUBNET && runCatching { java.net.URI(value).let { it.scheme in setOf("tcp", "udp", "wg", "ws", "wss", "quic") && !it.host.isNullOrBlank() && it.port in 1..65535 } }.getOrDefault(false).not() -> "请填写完整的协议、主机和端口"
                    else -> ""
                }
                if (fieldError.isEmpty()) {
                    if (current.index >= 0 && current.kind != EndpointKind.LISTENER) {
                        val group = if (current.kind == EndpointKind.PEER) "peer" else "proxy_network"
                        if (model.renameEntry(group, current.value, value, current.index)) edit = null
                        else fieldError = model.editorError.value
                    } else {
                        if (current.index < 0) entries.add(value) else entries[current.index] = value
                        setValues(current.kind, entries); edit = null
                    }
                }
            }) { Text("完成") } }, dismissButton = { TextButton(onClick = { edit = null }) { Text("取消") } })
    }
}

@Composable fun EditorField(label: String, value: String, onChange: (String) -> Unit, hint: String = "", number: Boolean = false, mono: Boolean = false) {
    OutlinedTextField(value, onChange, Modifier.fillMaxWidth(), label = { Text(label) }, singleLine = true,
        supportingText = if (hint.isBlank()) null else ({ Text(hint) }),
        keyboardOptions = KeyboardOptions(keyboardType = if (number) KeyboardType.Number else KeyboardType.Text),
        textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = if (mono) FontFamily.Monospace else FontFamily.Default))
}
