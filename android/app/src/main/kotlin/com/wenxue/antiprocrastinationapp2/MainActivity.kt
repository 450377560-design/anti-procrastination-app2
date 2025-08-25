package com.wenxue.antiprocrastinationapp2

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "focus_bridge"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FocusBridge.init(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startFocus" -> {
                        val minutes = call.argument<Int>("minutes") ?: 25
                        val lock = call.argument<Boolean>("lock") ?: false
                        val ok = FocusService.start(this, minutes, lock)
                        result.success(ok)
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
                    else -> result.notImplemented()
                }
            }
    }
}
