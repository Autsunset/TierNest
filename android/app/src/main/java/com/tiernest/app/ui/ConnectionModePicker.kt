package com.tiernest.app.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Shield
import androidx.compose.material.icons.rounded.VpnKey
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.tiernest.app.AppModel
import com.tiernest.app.data.ConnectionMode

@Composable fun ConnectionModePicker(model: AppModel) {
    val prefs by model.prefs.collectAsStateWithLifecycle()
    val busy by model.busy.collectAsStateWithLifecycle()
    var pending by remember { mutableStateOf<ConnectionMode?>(null) }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        ConnectionMode.entries.forEach { mode ->
            val selected = prefs.connectionMode == mode
            Surface(onClick = {
                if (!busy && !selected) {
                    if (prefs.requested) pending = mode else model.chooseConnectionMode(mode)
                }
            }, modifier = Modifier.weight(1f), enabled = !busy,
                shape = RoundedCornerShape(20.dp),
                color = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainerLow,
                border = BorderStroke(1.dp, if (selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.5f) else MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))) {
                Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(if (mode == ConnectionMode.ROOT) Icons.Rounded.Shield else Icons.Rounded.VpnKey, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
                    Column {
                        Text(mode.label, fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal, style = MaterialTheme.typography.titleSmall)
                        Text(if (mode == ConnectionMode.ROOT) "可与其他 VPN 共存" else "无需 Root 权限", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
    pending?.let { mode -> AlertDialog(onDismissRequest = { pending = null }, title = { Text("切换到${mode.label}？") },
        text = { Text("会先断开当前连接，保留配置。切换后由你重新连接。VPN 模式会使用系统 VPN 槽位。") },
        confirmButton = { TextButton(onClick = { model.chooseConnectionMode(mode); pending = null }) { Text("断开并切换") } },
        dismissButton = { TextButton(onClick = { pending = null }) { Text("取消") } }) }
}
