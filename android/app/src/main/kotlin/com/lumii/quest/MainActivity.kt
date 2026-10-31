package com.lumii.quest

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lumii/call_overlay"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isOverlayGranted" -> result.success(Settings.canDrawOverlays(this))
                "requestOverlayPermission" -> {
                    if (!Settings.canDrawOverlays(this)) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                    }
                    result.success(null)
                }
                "show" -> {
                    val avatarUrl = call.argument<String>("avatarUrl") ?: ""
                    val name = call.argument<String>("name") ?: "Lumii Call"
                    CallOverlayService.show(this, avatarUrl, name)
                    result.success(null)
                }
                "hide" -> {
                    CallOverlayService.hide(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
