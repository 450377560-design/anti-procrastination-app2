package com.wenxue.antiprocrastinationapp2

import android.app.*
import android.content.*
import android.os.*
import androidx.core.app.NotificationCompat
import kotlin.math.max

class FocusService : Service() {
    companion object {
        private const val NOTIF_ID = 1001
        private const val CHANNEL_ID = "focus_service"
        private const val ACTION_STOP = "com.wenxue.antiprocrastinationapp2.ACTION_STOP"
        private const val EXTRA_END = "endAt"
        private const val EXTRA_LOCK = "lock"

        fun start(ctx: Context, minutes: Int, lock: Boolean): Boolean {
            val endAt = SystemClock.elapsedRealtime() + minutes * 60_000L
            val i = Intent(ctx, FocusService::class.java).apply {
                putExtra(EXTRA_END, endAt)
                putExtra(EXTRA_LOCK, lock)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ctx.startForegroundService(i)
            } else {
                ctx.startService(i)
            }
            return true
        }

        fun stop(ctx: Context): Boolean {
            val i = Intent(ctx, FocusService::class.java).apply { action = ACTION_STOP }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ctx.startForegroundService(i)
            } else {
                ctx.startService(i)
            }
            return true
        }
    }

    private var endAt: Long = 0L
    private var lock: Boolean = false
    private val handler = Handler(Looper.getMainLooper())

    private val tick = object : Runnable {
        override fun run() {
            val remaining = max(0L, endAt - SystemClock.elapsedRealtime())
            val sec = (remaining / 1000L).toInt()
            updateNotification(sec)
            FocusBridge.onTick(sec)
            if (remaining <= 0) {
                FocusBridge.onFinish()
                stopSelf()
            } else {
                handler.postDelayed(this, 1000L)
            }
        }
    }

    private val userPresentReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (Intent.ACTION_USER_PRESENT == intent?.action) {
                FocusBridge.onInterruption()
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        NotificationHelper.ensureChannel(this, CHANNEL_ID, "专注计时")
        registerReceiver(userPresentReceiver, IntentFilter(Intent.ACTION_USER_PRESENT))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            // 通知停止/外部停止 -> 视为打断
            FocusBridge.onInterruption()
            stopSelf()
            return START_NOT_STICKY
        }

        endAt = intent?.getLongExtra(EXTRA_END, 0L) ?: endAt
        lock = intent?.getBooleanExtra(EXTRA_LOCK, false) ?: lock

        startForeground(NOTIF_ID, buildNotification(0))
        handler.removeCallbacksAndMessages(null)
        handler.post(tick)

        if (lock) launchLockActivity()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        handler.removeCallbacksAndMessages(null)
        try { unregisterReceiver(userPresentReceiver) } catch (_: Exception) {}
        FocusBridge.onStop()
    }

    private fun buildNotification(remainingSec: Int): Notification {
        val stopIntent = Intent(this, FocusService::class.java).apply { action = ACTION_STOP }
        val stopPI = PendingIntent.getService(
            this, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val contentPI = PendingIntent.getActivity(
            this, 1, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("专注中")
            .setContentText("剩余 ${remainingSec}s · 点击停止")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentPI)
            .addAction(NotificationCompat.Action(0, "停止", stopPI))
            .build()
    }

    private fun updateNotification(remainingSec: Int) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID, buildNotification(remainingSec))
    }

    private fun launchLockActivity() {
        val i = Intent(this, LockActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("endAt", endAt)
        }
        startActivity(i)
    }

    override fun onBind(intent: Intent?) = null
}
