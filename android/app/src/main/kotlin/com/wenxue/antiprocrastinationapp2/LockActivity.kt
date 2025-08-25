package com.wenxue.antiprocrastinationapp2

import android.os.*
import android.view.*
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import kotlin.math.max

class LockActivity : AppCompatActivity() {
    private var endAt: Long = 0L
    private lateinit var tv: TextView
    private val handler = Handler(Looper.getMainLooper())
    private val ticker = object : Runnable {
        override fun run() {
            val remaining = max(0L, endAt - SystemClock.elapsedRealtime())
            val s = remaining / 1000
            tv.text = format(s)
            if (remaining <= 0) finish() else handler.postDelayed(this, 1000L)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
            View.SYSTEM_UI_FLAG_FULLSCREEN or
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION

        val lp = window.attributes
        lp.screenBrightness = 0.03f // 3%，可做成设置项
        window.attributes = lp

        tv = TextView(this).apply {
            textSize = 64f
            setTextColor(0xFFFFFFFF.toInt())
            text = ""
            gravity = Gravity.CENTER
            setBackgroundColor(0xFF000000.toInt())
        }
        setContentView(tv)

        endAt = intent.getLongExtra("endAt", 0L)
    }

    override fun onResume() {
        super.onResume()
        handler.post(ticker)
    }

    override fun onPause() {
        super.onPause()
        handler.removeCallbacks(ticker)
    }

    private fun format(sec: Long): String {
        val m = sec / 60
        val s = sec % 60
        return String.format("%02d:%02d", m, s)
    }
}
