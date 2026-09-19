package com.tiernest.app.data

import org.json.JSONArray
import org.json.JSONObject

data class Peer(
    val name: String, val ipv4: String, val hops: Int?, val latency: Double?,
    val nextHop: String, val subnets: List<String>,
    val nextHopIpv4: String = "", val version: String = "", val id: String = "", val nextHopId: String = "",
    val protocols: List<String> = emptyList(),
)

object PeerCodec {
    fun decode(text: String): List<Peer> {
        val trimmed = text.trim()
        val array = if (trimmed.startsWith("[")) JSONArray(trimmed) else {
            val obj = JSONObject(trimmed)
            obj.optJSONArray("data") ?: obj.optJSONArray("routes")
                ?: error("无法识别核心的节点响应")
        }
        return (0 until array.length()).map { index ->
            val item = array.getJSONObject(index)
            Peer(
                name = item.optString("hostname", "未命名节点"),
                ipv4 = item.optString("ipv4", ""),
                hops = item.opt("path_len")?.toString()?.toIntOrNull()?.takeIf { it >= 0 },
                latency = item.optDouble("next_hop_lat", Double.NaN).takeIf { it.isFinite() && it >= 0 },
                nextHop = item.optString("next_hop_hostname", ""),
                subnets = item.optString("proxy_cidrs", "").split(',').map { it.trim() }.filter { it.isNotEmpty() && it != "-" },
                nextHopIpv4 = item.optString("next_hop_ipv4", ""), version = item.optString("version", ""),
                id = item.optString("peer_id", ""), nextHopId = item.optString("next_hop_peer_id", ""),
                protocols = item.optJSONArray("protocols")?.let { list -> (0 until list.length()).map { list.getString(it) } }.orEmpty(),
            )
        }
    }
}
