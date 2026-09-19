package com.tiernest.app.service

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import com.tiernest.app.TierNestApp
import com.tiernest.app.data.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.Inet4Address
import java.net.Proxy
import java.net.URL

data class WifiLink(val network: Network, val iface: String, val gateway: String)

class HomeDetector(private val app: TierNestApp) {
    private val cm = app.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private var failedId: String? = null
    private var failures = 0
    private var trustedId: String? = null

    fun wifi(): WifiLink? = cm.allNetworks.firstNotNullOfOrNull { network ->
        val caps = cm.getNetworkCapabilities(network) ?: return@firstNotNullOfOrNull null
        if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) || !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)) return@firstNotNullOfOrNull null
        val props = cm.getLinkProperties(network) ?: return@firstNotNullOfOrNull null
        val iface = props.interfaceName ?: return@firstNotNullOfOrNull null
        val gateway = props.routes.firstOrNull { it.isDefaultRoute && it.gateway is Inet4Address }?.gateway?.hostAddress
            ?: return@firstNotNullOfOrNull null
        WifiLink(network, iface, gateway)
    }

    fun physicalNetworks(): List<String> = cm.allNetworks.flatMap { network ->
        val caps = cm.getNetworkCapabilities(network)
        if (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN) == true) {
            cm.getLinkProperties(network)?.linkAddresses.orEmpty().filter { it.address is Inet4Address }
                .map { "${it.address.hostAddress}/${it.prefixLength}" }
        } else emptyList()
    }

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
        check(probe(link.network, target, port)) { "通过当前 Wi-Fi 无法访问该 HTTP 地址" }
        val mac = app.engine.gatewayMac(link.iface, link.gateway)
        check(wifi() == link) { "Wi-Fi 已变化，请重试" }
        return HomeNetwork(link.iface, link.gateway, mac, target, port)
    }

    suspend fun check(prefs: Preferences): Boolean {
        if (!prefs.automatic || prefs.homes.isEmpty()) return false
        val link = wifi() ?: return reset()
        val possible = prefs.homes.filter { it.iface == link.iface && it.gateway == link.gateway }
        if (possible.isEmpty()) return reset()
        val mac = app.engine.gatewayMac(link.iface, link.gateway)
        val home = possible.firstOrNull { it.mac == mac } ?: return reset()
        val verified = prefs.detection == DetectionMode.EVENT || probe(link.network, home.target, home.port)
        if (wifi() != link) return reset()
        if (verified) {
            failures = 0; failedId = null; trustedId = home.id
            return true
        }
        failures = if (failedId == home.id) failures + 1 else 1
        failedId = home.id
        // Only retain standby for a single transient failure on the same gateway.
        return trustedId == home.id && failures < 2
    }

    private fun reset(): Boolean { failures = 0; failedId = null; trustedId = null; return false }

    private suspend fun probe(network: Network, target: String, port: Int): Boolean = withContext(Dispatchers.IO) {
        runCatching {
            // Bind the HTTP socket to the physical Network, not the default VPN.
            val connection = network.openConnection(URL("http://$target:$port/"), Proxy.NO_PROXY) as HttpURLConnection
            try {
                connection.connectTimeout = 2500; connection.readTimeout = 2500
                connection.instanceFollowRedirects = false; connection.requestMethod = "HEAD"
                connection.responseCode in 100..599
            } finally { connection.disconnect() }
        }.getOrDefault(false)
    }
}
