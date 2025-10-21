package com.example.carpal_app

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.carpal_app/phone_launcher"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "openDialer" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val rawNumber = arguments?.get("phoneNumber") as? String
                    val phoneNumber = rawNumber?.trim()

                    if (phoneNumber.isNullOrEmpty()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    val dialIntent = Intent(Intent.ACTION_DIAL).apply {
                        data = Uri.parse("tel:$phoneNumber")
                    }

                    val packageManager = applicationContext.packageManager
                    if (dialIntent.resolveActivity(packageManager) != null) {
                        try {
                            startActivity(dialIntent)
                            result.success(true)
                        } catch (error: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}
