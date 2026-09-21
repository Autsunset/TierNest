package com.tiernest.app.service

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import com.tiernest.app.TierNestApp
import com.tiernest.app.data.*
import java.net.Inet4Address

data class WifiLink(val network: Network, val iface: String, val gateway: String, val source: String)

class HomeDetector(private val app: TierNestApp) {
    private val cm = app.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val trust = HomeTrust()

    fun wifi(): WifiLink? = cm.allNetworks.firstNotNullOfOrNull { network ->
        val caps = cm.getNetworkCapabilities(network) ?: return@firstNotNullOfOrNull null
        if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) || !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)) return@firstNotNullOfOrNull null
        val props = cm.getLinkProperties(network) ?: return@firstNotNullOfOrNull null
        val iface = props.interfaceName ?: return@firstNotNullOfOrNull null
        val gateway = props.routes.firstOrNull { it.isDefaultRoute && it.gateway is Inet4Address }?.gateway?.hostAddress
            ?: return@firstNotNullOfOrNull null
        val source = props.linkAddresses.firstOrNull { it.address is Inet4Address }?.address?.hostAddress
            ?: return@firstNotNullOfOrNull null
        WifiLink(network, iface, gateway, source)
    }

    fun physicalNetworks(): List<String> = (cm.allNetworks.flatMap { network ->
        val caps = cm.getNetworkCapabilities(network)
        if (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN) == true) {
            cm.getLinkProperties(network)?.linkAddresses.orEmpty().filter { it.address is Inet4Address }
                .map { "${it.address.hostAddress}/${it.prefixLength}" }
        } else emptyList()
    } + runCatching {
        // Hotspot downstreams are often absent from ConnectivityManager's
        // upstream Networks. They must still be excluded from overlay routes.
        java.net.NetworkInterface.getNetworkInterfaces().toList().filter { iface ->
            iface.isUp && iface.name.matches(Regex("(?:wlan[0-9]+|ap[0-9]+|ap_[A-Za-z0-9_-]+|apbr[A-Za-z0-9_-]*|swlan[0-9]+|softap[0-9]+|br_tether[A-Za-z0-9_-]*)"))
        }.flatMap { iface -> iface.interfaceAddresses.filter { it.address is Inet4Address }
            .map { "${it.address.hostAddress}/${it.networkPrefixLength}" } }
    }.getOrDefault(emptyList())).distinct()

    fun physicalSignature(): String = cm.allNetworks.mapNotNull { network ->
        val caps = cm.getNetworkCapabilities(network)
        if (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN) == true &&
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
            val props = cm.getLinkProperties(network)
            "$network:${props?.interfaceName}:${props?.linkAddresses?.map { it.toString() }?.sorted()}:" +
                props?.routes?.filter { it.isDefaultRoute }?.map { it.gateway?.hostAddress }?.sortedBy { it }
        } else null
    }.sorted().joinToString()

    fun vpnActive(): Boolean = cm.allNetworks.any { cm.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true }
    fun networkLabel(): String = cm.allNetworks.mapNotNull { network ->
        val caps = cm.getNetworkCapabilities(network) ?: return@mapNotNull null
        if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)) return@mapNotNull null
        when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "移动数据"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "以太网"
            else -> null
        }
    }.distinct().joinToString(" / ").ifBlank { "未检测到物理网络" }

    suspend fun learn(target: String, port: Int): HomeNetwork {
        require(RoutePlanner.cidr(target)?.prefix == 32 && !target.contains('/')) { "请输入虚拟 IPv4 地址" }
        require(port in 1..65535) { "端口范围是 1–65535" }
        val link = wifi() ?: error("请先连接提供组网代理的 Wi-Fi")
        val mac = app.engine.gatewayMac(link.iface, link.gateway)
        check(app.engine.probeWifi(link.iface, link.gateway, link.source, target, port, mac)) {
            "通过当前 Wi-Fi 无法访问该 HTTP 地址，请确认家庭网关已提供组网代理"
        }
        check(wifi() == link) { "Wi-Fi 已变化，请重试" }
        return HomeNetwork(link.iface, link.gateway, mac, target, port, wifiVerified = true)
    }

    suspend fun check(prefs: Preferences): Boolean {
        try { return inspect(prefs) }
        catch (error: Exception) { trust.reset(); throw error }
    }

    fun reset() { trust.reset() }

    private suspend fun inspect(prefs: Preferences): Boolean {
        if (!prefs.automatic || prefs.homes.isEmpty()) return trust.reset()
        val link = wifi() ?: return trust.reset()
        val possible = prefs.homes.filter { it.iface == link.iface && it.gateway == link.gateway }
        if (possible.isEmpty()) return trust.reset()
        val mac = app.engine.gatewayMac(link.iface, link.gateway)
        val home = possible.firstOrNull { it.mac == mac } ?: return trust.reset()
        check(home.wifiVerified) { "此家庭网络需要重新验证，请到设置 → 家庭网络完成验证" }
        val verified = prefs.detection == DetectionMode.EVENT ||
            app.engine.probeWifi(link.iface, link.gateway, link.source, home.target, home.port, mac)
        if (wifi() != link) return trust.reset()
        return trust.observe("$link|${home.id}|${home.target}:${home.port}|${prefs.detection}", verified)
    }
}
