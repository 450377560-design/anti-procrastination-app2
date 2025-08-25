package com.wenxue.antiprocrastinationapp2

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object FocusBridge {
    private const val CHANNEL_NAME = "focus_bridge"
    private var channel: MethodChannel? = null

    fun init(engine: FlutterEngine) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
    }

    fun onInterruption() {
        channel?.invokeMethod("onInterruption", null)
    }

    fun onTick(remainingSec: Int) {
        channel?.invokeMethod("onTick", mapOf("remaining" to remainingSec))
    }

    fun onFinish() {
        channel?.invokeMethod("onFinish", null)
    }

    fun onStop() {
        channel?.invokeMethod("onStop", null)
    }
}
