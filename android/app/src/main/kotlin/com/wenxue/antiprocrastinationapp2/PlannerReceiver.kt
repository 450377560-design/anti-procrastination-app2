package com.wenxue.antiprocrastinationapp2

import android.app.*
import android.content.*
import androidx.core.app.NotificationCompat

class PlannerReceiver : BroadcastReceiver() {
    companion object {
        private const val REQ = 2001
        private const val CHANNEL_ID = "planner"
        private const val PREFS = "planner_prefs"
        private const val KEY_HOUR = "hour"
        private const val KEY_MINUTE = "minute"
        private const val KEY_ENABLED = "enabled"

        fun enableDailyPlanner(ctx: Context, hour: Int, minute: Int) {
            val sp = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            sp.edit().putInt(KEY_HOUR, hour).putInt(KEY_MINUTE, minute).putBoolean(KEY_ENABLED, true).apply()
            schedule(ctx, hour, minute)
        }

        fun disableDailyPlanner(ctx: Context) {
            val sp = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            sp.edit().putBoolean(KEY_ENABLED, false).apply()
            cancel(ctx)
        }

        fun restoreIfNeeded(ctx: Context) {
            val sp = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (sp.getBoolean(KEY_ENABLED, false)) {
                schedule(ctx, sp.getInt(KEY_HOUR, 21), sp.getInt(KEY_MINUTE, 30))
            }
        }

        private fun pi(ctx: Context): PendingIntent {
            val i = Intent(ctx, PlannerReceiver::class.java)
            return PendingIntent.getBroadcast(ctx, REQ, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        private fun schedule(ctx: Context, hour: Int, minute: Int) {
            NotificationHelper.ensureChannel(ctx, CHANNEL_ID, "夜间规划")
            val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager

            val now = java.util.Calendar.getInstance()
            val target = java.util.Calendar.getInstance().apply {
                set(java.util.Calendar.HOUR_OF_DAY, hour)
                set(java.util.Calendar.MINUTE, minute)
                set(java.util.Calendar.SECOND, 0)
                set(java.util.Calendar.MILLISECOND, 0)
                if (before(now)) add(java.util.Calendar.DAY_OF_YEAR, 1)
            }
            val triggerAt = target.timeInMillis

            am.setInexactRepeating(
                AlarmManager.RTC_WAKEUP,
                triggerAt,
                AlarmManager.INTERVAL_DAY,
                pi(ctx)
            )
        }

        private fun cancel(ctx: Context) {
            val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.cancel(pi(ctx))
        }
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val content = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java).apply {
                putExtra("openTomorrow", true)
            }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val n = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle("夜间规划")
            .setContentText("为明日排好任务，一键搬移未完成项 →")
            .setAutoCancel(true)
            .setContentIntent(content)
            .build()

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(2002, n)
    }
}
