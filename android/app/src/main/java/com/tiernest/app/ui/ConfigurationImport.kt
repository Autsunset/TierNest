package com.tiernest.app.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import com.tiernest.app.AppModel
import com.tiernest.app.data.ConfigCodec
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream

@Composable fun rememberConfigurationImport(model: AppModel, onImported: () -> Unit): () -> Unit {
    val context = LocalContext.current
    val latestImported by rememberUpdatedState(onImported)
    var pending by remember { mutableStateOf<String?>(null) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) model.task {
            val text = context.contentResolver.openInputStream(uri)?.use { input ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (output.size() <= ConfigCodec.MAX_BYTES) {
                    val count = input.read(buffer, 0, minOf(buffer.size, ConfigCodec.MAX_BYTES + 1 - output.size()))
                    if (count < 0) break
                    output.write(buffer, 0, count)
                }
                require(output.size() <= ConfigCodec.MAX_BYTES) { "配置不能超过 256 KiB" }
                Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(output.toByteArray())).toString()
            } ?: error("无法读取配置文件")
            ConfigCodec.parse(text)
            withContext(Dispatchers.Main) {
                if (model.editor.value.dirty) pending = text
                else { model.importDraft(text); latestImported() }
            }
        }
    }
    pending?.let { text -> AlertDialog(onDismissRequest = { pending = null }, title = { Text("替换当前草稿？") },
        text = { Text("当前有未保存的修改。导入后可先检查内容，已保存的配置不会改变。") },
        confirmButton = { TextButton(onClick = { model.importDraft(text); pending = null; latestImported() }) { Text("导入草稿") } },
        dismissButton = { TextButton(onClick = { pending = null }) { Text("取消") } }) }
    return { picker.launch(arrayOf("*/*")) }
}
