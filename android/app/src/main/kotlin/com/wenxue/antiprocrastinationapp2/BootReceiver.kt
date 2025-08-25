package com.wenxue.antiprocrastinationapp2

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED) {
            PlannerReceiver.restoreIfNeeded(context)
        }
    }
}
