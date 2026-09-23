package com.tiernest.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.tiernest.app.Dashboard
import com.tiernest.app.data.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun PeersScreen(state: Dashboard) {
    var view by rememberSaveable { mutableIntStateOf(0) }
    var selected by remember { mutableStateOf<Peer?>(null) }
    val sorted = remember(state.peers) { state.peers.sortedBy { it.hops ?: Int.MAX_VALUE } }
    val topology = remember(state.peers, state.cidr) { TopologyBuilder.build(state.peers, state.cidr) }
    val counts = remember(sorted) { Triple(sorted.count { it.hops == 1 }, sorted.count { (it.hops ?: 0) > 1 }, sorted.flatMap { it.subnets }.distinct().size) }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item { SettingsHeader("网络节点", "NETWORK NODES") }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                NodeCount("直连", counts.first, Modifier.weight(1f))
                NodeCount("多跳", counts.second, Modifier.weight(1f))
                NodeCount("共享网段", counts.third, Modifier.weight(1f))
            }
        }
        item { ChoiceStrip(listOf("节点列表", "路由拓扑"), view, { view = it }, Modifier.fillMaxWidth()) }
        if (sorted.isEmpty()) item { SettingsCard {
            Icon(Icons.Rounded.Hub, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(36.dp))
            Text(if (state.active) "正在发现你的设备" else "连接后查看你的设备", style = MaterialTheme.typography.titleLarge)
            SmallNote("连接建立后显示真实节点、下一跳和共享网段。")
        } } else if (view == 0) {
            items(sorted) { peer -> PeerCard(peer, onClick = { selected = peer }) }
        } else {
            item { SmallNote("以本机为起点的路由视图。实线表示已确认的相邻节点，虚线表示未知或折叠路径及共享子网。点按节点查看详情。") }
            items(topology.rows, key = { it.node.key }) { row ->
                Row(Modifier.height(IntrinsicSize.Min)) {
                    if (row.depth > 0) TopologyBranch(row, Modifier.width((row.depth * 20).dp).fillMaxHeight())
                    val peer = row.node.peer
                    if (peer != null) PeerCard(peer, Modifier.weight(1f), row.edge?.label, onClick = { selected = peer })
                    else SettingsCard(Modifier.weight(1f), padding = 14.dp) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(if (row.node.subnet) Icons.Rounded.Lan else Icons.Rounded.HelpOutline, null, modifier = Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(row.node.name, style = MaterialTheme.typography.titleSmall)
                        }
                        Text(row.node.address.ifBlank { "未上报" }, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
            items(topology.warnings) { SmallNote(it) }
        }
        if (sorted.isNotEmpty()) item { SmallNote("多跳节点的 RTT 是到下一跳的时延，完整路径可能更长。") }
    }
    selected?.let { original ->
        val current = state.peers.firstOrNull { if (original.id.isNotBlank()) it.id == original.id else it.name == original.name && it.ipv4 == original.ipv4 }
        val peer = current ?: original
        ModalBottomSheet(onDismissRequest = { selected = null }) {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text(peer.name.ifBlank { "未命名节点" }, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                if (current == null) SmallNote("该节点已不在当前路由中，以下是最后收到的信息。")
                DetailLine("虚拟地址", peer.ipv4.ifBlank { "未上报" })
                DetailLine("连接路径", pathLabel(peer))
                DetailLine("节点 ID", peer.id.ifBlank { "未上报" })
                DetailLine("内核版本", peer.version.ifBlank { "未上报" })
                if (peer.hops != 0) {
                    DetailLine("下一跳", if (peer.hops == 1) "直达该节点" else peer.nextHop.ifBlank { "未上报" })
                    DetailLine("下一跳地址", peer.nextHopIpv4.ifBlank { "未上报" })
                    DetailLine("下一跳 RTT", peer.latency?.let { "%.1f ms".format(it) } ?: "未上报")
                }
                if (peer.protocols.isNotEmpty()) DetailLine("传输协议", peer.protocols.joinToString(" · "))
                DetailLine("共享网段", peer.subnets.joinToString("\n").ifBlank { "无" })
            }
        }
    }
}

@Composable private fun NodeCount(label: String, count: Int, modifier: Modifier) {
    SettingsCard(modifier, padding = 14.dp) {
        Text(count.toString(), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

private fun pathLabel(peer: Peer) = when (peer.hops) { 0 -> "本机"; 1 -> "直连"; null -> "路径未知"; else -> "${peer.hops} 跳" }

@Composable private fun PeerCard(peer: Peer, modifier: Modifier = Modifier, edgeLabel: String? = null, onClick: () -> Unit) {
    Surface(onClick = onClick, modifier = modifier.fillMaxWidth(), shape = RoundedCornerShape(22.dp), color = MaterialTheme.colorScheme.surfaceContainerLow) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(if (peer.hops == 0) Icons.Rounded.PhoneAndroid else Icons.Rounded.Devices, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(23.dp))
                Column(Modifier.weight(1f)) {
                    Text(peer.name.ifBlank { "未命名节点" }, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(peer.ipv4.ifBlank { "未分配 IPv4" }, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Icon(Icons.Rounded.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
            }
            Text(listOfNotNull(edgeLabel ?: pathLabel(peer), peer.latency?.let { "%.1f ms".format(it) }, peer.subnets.takeIf { it.isNotEmpty() }?.let { "${it.size} 个共享网段" }).joinToString(" · "),
                style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
        }
    }
}

@Composable private fun TopologyBranch(row: TopologyRow, modifier: Modifier) {
    val color = MaterialTheme.colorScheme.outlineVariant
    Canvas(modifier.semantics { contentDescription = row.edge?.label.orEmpty() }) {
        val step = 20.dp.toPx()
        row.rails.forEachIndexed { index, visible -> if (visible) {
            val x = step * index + step / 2
            drawLine(color, Offset(x, -12.dp.toPx()), Offset(x, size.height + 12.dp.toPx()), 1.5.dp.toPx())
        } }
        val x = size.width - step / 2
        val effect = if (row.edge?.dashed == true) PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 4.dp.toPx())) else null
        drawLine(color, Offset(x, -12.dp.toPx()), Offset(x, if (row.last) size.height / 2 else size.height + 12.dp.toPx()), 1.5.dp.toPx(), pathEffect = effect)
        drawLine(color, Offset(x, size.height / 2), Offset(size.width, size.height / 2), 1.5.dp.toPx(), pathEffect = effect)
    }
}
