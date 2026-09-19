package com.tiernest.app.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.tiernest.app.TierNestApp

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED)) return
        val prefs = (context.applicationContext as TierNestApp).store.load()
        if (prefs.boot && prefs.requested) ConnectionService.request(context, true)
    }
}
