package com.tiernest.app.data

import org.tomlj.Toml
import org.tomlj.TomlArray
import org.tomlj.TomlTable

data class NetworkForm(
    val name: String = "", val secret: String = "", val hostname: String = "",
    val ipv4: String = "", val dhcp: Boolean = true, val peers: String = "",
    val subnets: String = "",
    val instanceName: String = "tiernest", val listeners: List<String> = emptyList(),
    val mtu: String = "1380", val features: Map<String, Boolean> = FeatureOptions.defaults,
)

object FeatureOptions {
    // Defaults from the pinned EasyTier 2.6.4 gen_default_flags().
    val defaults = linkedMapOf("enable_encryption" to true, "enable_ipv6" to true,
        "latency_first" to false, "disable_p2p" to false, "bind_device" to true,
        "private_mode" to false, "disable_udp_hole_punching" to false,
        "disable_tcp_hole_punching" to false, "enable_kcp_proxy" to false, "use_smoltcp" to false)
}

/** TOML is data, never shell input. The original text is stored independently. */
object ConfigCodec {
    const val MAX_BYTES = 256 * 1024
    val template = """
        instance_name = "tiernest"
        dhcp = true
        listeners = []
        rpc_portal = "127.0.0.1:15888"

        [network_identity]
        network_name = ""
        network_secret = ""

        [flags]
        dev_name = "tiernest0"
        enable_encryption = true
        enable_ipv6 = true
        mtu = 1380
        no_tun = false
        enable_exit_node = false
    """.trimIndent() + "\n"

    fun parse(text: String): MutableMap<String, Any> {
        require(text.toByteArray().size <= MAX_BYTES) { "配置不能超过 256 KiB" }
        val result = Toml.parse(text)
        require(!result.hasErrors()) {
            // Parser diagnostics may echo secret values; report positions only.
            "TOML 格式错误：" + result.errors().joinToString { it.position().toString() }
        }
        return table(result)
    }

    private fun table(value: TomlTable): MutableMap<String, Any> = value.keySet()
        .associateWithTo(linkedMapOf()) { unpack(value.get(listOf(it))!!) }

    private fun unpack(value: Any): Any = when (value) {
        is TomlTable -> table(value)
        is TomlArray -> (0 until value.size()).map { unpack(value.get(it)) }
        else -> value
    }

    fun encode(values: Map<String, Any>): String = values.entries.joinToString("\n", postfix = "\n") {
        "${quote(it.key)} = ${literal(it.value)}"
    }

    private fun literal(value: Any): String = when (value) {
        is String -> quote(value)
        is Map<*, *> -> value.entries.joinToString(", ", "{ ", " }") { "${quote(it.key.toString())} = ${literal(it.value!!)}" }
        is List<*> -> value.joinToString(", ", "[", "]") { literal(it!!) }
        is Double -> when { value.isNaN() -> "nan"; value == Double.POSITIVE_INFINITY -> "inf"; value == Double.NEGATIVE_INFINITY -> "-inf"; else -> value.toString() }
        is java.time.LocalTime -> value.format(java.time.format.DateTimeFormatter.ISO_LOCAL_TIME)
        is java.time.LocalDateTime -> value.format(java.time.format.DateTimeFormatter.ISO_LOCAL_DATE_TIME)
        is java.time.OffsetDateTime -> value.format(java.time.format.DateTimeFormatter.ISO_OFFSET_DATE_TIME)
        else -> value.toString()
    }

    private fun quote(value: String): String = buildString {
        append('"')
        value.forEach { c ->
            when (c) {
                '"' -> append("\\\"")
                '\\' -> append("\\\\")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> if (c.code < 32 || c.code == 127) append("\\u%04x".format(c.code)) else append(c)
            }
        }
        append('"')
    }

    @Suppress("UNCHECKED_CAST")
    fun form(text: String): NetworkForm {
        val config = parse(text)
        val identity = config["network_identity"] as? Map<String, Any> ?: emptyMap()
        val peers = config["peer"] as? List<Map<String, Any>> ?: emptyList()
        val proxies = config["proxy_network"] as? List<Map<String, Any>> ?: emptyList()
        val flags = config["flags"] as? Map<String, Any> ?: emptyMap()
        return NetworkForm(
            name = identity["network_name"] as? String ?: "",
            secret = identity["network_secret"] as? String ?: "",
            hostname = config["hostname"] as? String ?: "",
            ipv4 = config["ipv4"] as? String ?: "",
            dhcp = config["dhcp"] as? Boolean ?: false,
            peers = peers.mapNotNull { it["uri"] as? String }.joinToString("\n"),
            subnets = proxies.mapNotNull { it["cidr"] as? String }.joinToString("\n"),
            instanceName = config["instance_name"] as? String ?: "tiernest",
            listeners = (config["listeners"] as? List<*>)?.filterIsInstance<String>().orEmpty(),
            mtu = flags["mtu"]?.toString() ?: "1380",
            features = FeatureOptions.defaults.mapValues { (key, default) -> flags[key] as? Boolean ?: default },
        )
    }

    @Suppress("UNCHECKED_CAST")
    fun updateForm(text: String, form: NetworkForm): String {
        val config = parse(text)
        val before = ConfigCodec.form(text)
        val identity = (config["network_identity"] as? Map<String, Any>).orEmpty().toMutableMap()
        identity["network_name"] = form.name.trim()
        identity["network_secret"] = form.secret
        config["network_identity"] = identity
        if (form.hostname.isBlank()) config.remove("hostname") else config["hostname"] = form.hostname.trim()
        config["dhcp"] = form.dhcp
        if (form.ipv4.isBlank()) config.remove("ipv4") else config["ipv4"] = form.ipv4.trim()
        // Preserve per-peer / per-subnet options for unchanged entries.
        fun rows(key: String, field: String, input: String): List<Map<String, Any>> {
            val old = (config[key] as? List<Map<String, Any>>).orEmpty().associateBy { it[field] }
            return input.lines().map { it.trim() }.filter { it.isNotEmpty() }.distinct().map {
                old[it] ?: mapOf(field to it)
            }
        }
        config["peer"] = rows("peer", "uri", form.peers)
        config["proxy_network"] = rows("proxy_network", "cidr", form.subnets)
        if (form.instanceName != before.instanceName) config["instance_name"] = form.instanceName.trim().ifBlank { "tiernest" }
        if (form.listeners != before.listeners) config["listeners"] = form.listeners
        val flags = (config["flags"] as? Map<String, Any>).orEmpty().toMutableMap()
        if (form.mtu != before.mtu) {
            val mtu = form.mtu.toLongOrNull()
            require(mtu != null && mtu in 576..9000) { "MTU 请输入 576–9000" }
            flags["mtu"] = mtu
        }
        FeatureOptions.defaults.keys.forEach { key ->
            if (form.features[key] != before.features[key]) flags[key] = form.features[key] ?: FeatureOptions.defaults.getValue(key)
        }
        if (flags.isNotEmpty()) config["flags"] = flags
        return encode(config)
    }

    @Suppress("UNCHECKED_CAST")
    fun renameEntry(text: String, group: String, old: String, replacement: String, index: Int = -1): String {
        require(group in setOf("peer", "proxy_network"))
        val field = if (group == "peer") "uri" else "cidr"
        val document = parse(text)
        val rows = document[group] as? List<Map<String, Any>> ?: error("原条目已不存在，请重新加载")
        val target = if (index < 0) rows.indexOfFirst { it[field] == old } else index
        require(target in rows.indices && rows[target][field] == old) { "原条目已变化，请重新打开编辑" }
        document[group] = rows.mapIndexed { position, entry -> if (position == target) entry + (field to replacement) else entry }
        return encode(document)
    }

    @Suppress("UNCHECKED_CAST")
    fun effective(text: String, mode: ConnectionMode = ConnectionMode.ROOT, defaultHostname: String? = null): String {
        val config = parse(text)
        val form = form(text)
        require(form.name.isNotBlank()) { "请先填写网络名称" }
        require(form.secret.isNotEmpty() || config.containsKey("credential")) { "请填写组网密钥" }
        require(form.dhcp || RoutePlanner.cidr(form.ipv4) != null) { "请启用 DHCP 或填写有效的虚拟 IPv4/CIDR" }
        require((config["exit_nodes"] as? List<*>)?.isNotEmpty() != true) { "与 VPN 共存模式不支持出口节点；请先在配置中移除 exit_nodes" }
        require(!config.containsKey("ipv6")) { "首版仅管理 IPv4 虚拟路由；暂不支持 ipv6 字段" }
        val flags = (config["flags"] as? Map<String, Any>).orEmpty().toMutableMap()
        require(flags["no_tun"] != true) { "App 组网需要 TUN，不能设置 no_tun=true" }
        require(flags["enable_exit_node"] != true) { "共存模式不能启用出口节点" }
        // Private runtime copy: importing or upgrading never rewrites source TOML.
        require(config["hostname"] == null || config["hostname"] is String) { "设备名称 hostname 必须是字符串" }
        if (form.hostname.isBlank() && !defaultHostname.isNullOrBlank()) config["hostname"] = defaultHostname
        flags["dev_name"] = if (mode == ConnectionMode.ROOT) "tiernest0" else ""
        flags["no_tun"] = false
        if (mode == ConnectionMode.VPN) flags["bind_device"] = false
        config["flags"] = flags
        config["rpc_portal"] = "127.0.0.1:15888"
        return encode(config)
    }
}
