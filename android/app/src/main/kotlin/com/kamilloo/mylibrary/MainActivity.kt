package com.kamilloo.mylibrary

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "my_library/offline_loans")
            .setMethodCallHandler { call, result ->
                if (call.method != "share") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val text = call.argument<String>("text")
                if (text.isNullOrBlank() || text.length > 4000) {
                    result.error("invalid_text", "Invalid loan sharing text", null)
                    return@setMethodCallHandler
                }
                try {
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, text)
                    }
                    startActivity(Intent.createChooser(send, "Udostępnij informacje"))
                    result.success(null)
                } catch (_: ActivityNotFoundException) {
                    result.error("unavailable", "No sharing application available", null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "my_library/reminders")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "notificationRationale" -> result.success(
                        Build.VERSION.SDK_INT >= 33 &&
                            shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)
                    )
                    else -> result.notImplemented()
                }
            }
    }
}
