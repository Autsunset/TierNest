package com.tiernest.app.service

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import com.tiernest.app.data.Preferences

/** Only inspect this app's most recent connection process, never other apps or
 * historical crashes predating the connection. No stack traces are collected. */
object ConnectionExitReason {
    fun previous(context: Context, prefs: Preferences): String {
        val fallback = "上次连接已中断，暂时无法确认退出原因；可直接重新连接"
        if (Build.VERSION.SDK_INT < 30 || prefs.sessionProcessId == 0 || prefs.sessionStartedAt == 0L) return fallback
        val exit = runCatching {
            context.getSystemService(ActivityManager::class.java)
                .getHistoricalProcessExitReasons(context.packageName, prefs.sessionProcessId, 1)
                .firstOrNull { it.processName == context.packageName && it.timestamp >= prefs.sessionStartedAt }
        }.getOrNull() ?: return fallback
        val reason = when (exit.reason) {
            ApplicationExitInfo.REASON_LOW_MEMORY -> "系统因内存不足回收了应用"
            ApplicationExitInfo.REASON_CRASH -> "应用发生崩溃"
            ApplicationExitInfo.REASON_CRASH_NATIVE -> "原生进程发生崩溃"
            ApplicationExitInfo.REASON_ANR -> "应用无响应，被系统停止"
            ApplicationExitInfo.REASON_USER_REQUESTED -> "应用被用户或系统管理操作停止"
            ApplicationExitInfo.REASON_SIGNALED -> "应用进程被终止（信号 ${exit.status}）"
            ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "系统因资源占用停止了应用"
            else -> return fallback
        }
        return "上次连接已中断：$reason。可直接重新连接"
    }
}
