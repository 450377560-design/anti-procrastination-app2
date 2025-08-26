package com.wenxue.antiprocrastinationapp2

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class MainActivity : FlutterActivity() {
    private val CHANNEL = "focus_bridge"
    private val REQ_NOTIF = 10086
    private var notifResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FocusBridge.init(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startFocus" -> {
                        val minutes = call.argument<Int>("minutes") ?: 25
                        val lock = call.argument<Boolean>("lock") ?: false

                        // 计算结束时间（供锁屏页显示倒计时）
                        val endAt = SystemClock.elapsedRealtime() + minutes * 60_000L

                        // 1) 先启动计时的前台服务（不再让服务去拉起锁屏 Activity）
                        FocusService.start(this, minutes, /*lock=*/ false)

                        // 2) 再由前台页面直接启动 LockActivity —— 规避“后台启动界面”限制
                        if (lock) {
                            val i = Intent(this, LockActivity::class.java).apply {
                                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                                putExtra("endAt", endAt)
                            }
                            startActivity(i)
                        }
                        result.success(true)
                    }

                    "stopFocus" -> {
                        val ok = FocusService.stop(this)
                        result.success(ok)
                    }

                    "plannerEnable" -> {
                        val hour = call.argument<Int>("hour") ?: 21
                        val minute = call.argument<Int>("minute") ?: 30
                        PlannerReceiver.enableDailyPlanner(this, hour, minute)
                        result.success(true)
                    }
                    "plannerDisable" -> {
                        PlannerReceiver.disableDailyPlanner(this)
                        result.success(true)
                    }

                    // 请求通知权限（Android 13+）
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            val granted = ContextCompat.checkSelfPermission(
                                this, Manifest.permission.POST_NOTIFICATIONS
                            ) == PackageManager.PERMISSION_GRANTED
                            if (granted) {
                                result.success(true)
                            } else {
                                notifResult = result
                                ActivityCompat.requestPermissions(
                                    this,
                                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                    REQ_NOTIF
                                )
                            }
                        } else {
                            result.success(true)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_NOTIF) {
            val ok = grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
            notifResult?.success(ok)
            notifResult = null
        }
    }
}
