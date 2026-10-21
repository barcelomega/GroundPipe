package com.barcelomega.groundpipe

import android.webkit.CookieManager
import android.content.Intent
import com.barcelomega.groundpipe.player.PlaybackBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var playbackBridge: PlaybackBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "ngmusic/cookies").setMethodCallHandler { call, result ->
            when (call.method) {
                "getCookies" -> {
                    val url = call.argument<String>("url") ?: ""
                    result.success(CookieManager.getInstance().getCookie(url) ?: "")
                }
                "clearCookies" -> {
                    CookieManager.getInstance().removeAllCookies(null)
                    CookieManager.getInstance().flush()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "ngmusic/share").setMethodCallHandler { call, result ->
            when (call.method) {
                "shareText" -> {
                    val text = call.argument<String>("text")
                    if (text.isNullOrBlank()) {
                        result.error("invalid_text", "Share text is empty", null)
                    } else {
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, text)
                        }
                        startActivity(Intent.createChooser(intent, null))
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        playbackBridge = PlaybackBridge(this, messenger)
    }

    override fun onDestroy() {
        playbackBridge?.release()
        super.onDestroy()
    }
}
