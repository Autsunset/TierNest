package com.tiernest.app.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import com.tiernest.app.AppModel
import com.tiernest.app.BuildConfig
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

/** The system picker works on Android 8+ without Root or storage permissions. */
@Composable fun rememberDiagnosticsExport(model: AppModel): () -> Unit {
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/plain")) { uri ->
        if (uri != null) model.exportDiagnostics(uri)
    }
    return {
        val date = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss"))
        val suffix = java.util.UUID.randomUUID().toString().take(8)
        try { picker.launch("TierNest-diagnostics-${BuildConfig.VERSION_NAME}-$date-$suffix.txt") }
        catch (error: Exception) { model.diagnosticExportUnavailable(error) }
    }
}
