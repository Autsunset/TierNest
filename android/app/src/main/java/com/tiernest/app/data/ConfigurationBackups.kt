package com.tiernest.app.data

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

/** Scoped Download backups for VPN users. No su, shell or all-files permission. */
class ConfigurationBackups(private val context: Context) {
    suspend fun create(text: String): String = withContext(Dispatchers.IO) {
        val bytes = text.toByteArray(Charsets.UTF_8)
        val name = "app-${SimpleDateFormat("yyyyMMdd-HHmmss", Locale.ROOT).format(Date())}-${UUID.randomUUID().toString().take(8)}.toml"
        if (Build.VERSION.SDK_INT >= 29) {
            val resolver = context.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, "application/toml")
                put(MediaStore.Downloads.RELATIVE_PATH, "Download/TierNest/backups")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: error("无法创建 Download 备份")
            try {
                resolver.openOutputStream(uri, "w")?.use { it.write(bytes) } ?: error("无法写入备份")
                val copy = resolver.openInputStream(uri)?.use { it.readBytes() } ?: error("无法校验备份")
                check(bytes.contentEquals(copy)) { "备份校验失败，原配置保留" }
                check(resolver.update(uri, ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }, null, null) == 1)
                var actualName = name
                resolver.query(uri, arrayOf(MediaStore.Downloads.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) actualName = it.getString(0)
                }
                "Download/TierNest/backups/$actualName"
            } catch (error: Exception) { resolver.delete(uri, null, null); throw error }
        } else {
            check(ContextCompat.checkSelfPermission(context, Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED) {
                "Android 8/9 需要存储权限：请在系统应用权限中允许文件访问，再创建 Download 备份"
            }
            @Suppress("DEPRECATION")
            val directory = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "TierNest/backups")
            check(directory.isDirectory || directory.mkdirs()) { "Download 目录不可写，原配置保留" }
            val file = File(directory, name)
            check(file.createNewFile()) { "备份文件已存在，未覆盖" }
            file.writeBytes(bytes)
            check(bytes.contentEquals(file.readBytes())) { "备份校验失败，原配置保留" }
            file.absolutePath
        }
    }
}
