package com.kamilloo.mylibrary

import android.Manifest
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
