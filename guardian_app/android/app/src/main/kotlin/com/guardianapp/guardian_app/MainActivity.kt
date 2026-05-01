package com.guardianapp.guardian_app

import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val batteryChannel = "com.guardianapp.guardian_app/battery"
    private val shareChannelName = "com.guardianapp.guardian_app/share"
    private var pendingShareIntent: Intent? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Store initial share intent so Flutter can consume it after engine starts.
        if (intent?.action == Intent.ACTION_SEND || intent?.action == Intent.ACTION_SEND_MULTIPLE) {
            pendingShareIntent = intent
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, batteryChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIgnoringBatteryOptimizations" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(POWER_SERVICE) as PowerManager
                            result.success(pm.isIgnoringBatteryOptimizations(packageName))
                        } else {
                            result.success(true)
                        }
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                            )
                            intent.data = Uri.parse("package:$packageName")
                            startActivity(intent)
                            result.success(null)
                        } else {
                            result.success(null)
                        }
                    }
                    "clearAllNotifications" -> {
                        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                        nm.cancelAll()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSharedData" -> {
                        result.success(extractShareData(pendingShareIntent))
                        pendingShareIntent = null
                    }
                    "readUri" -> {
                        val uriString = call.argument<String>("uri")
                        if (uriString == null) {
                            result.error("INVALID_ARGS", "uri is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val uri = Uri.parse(uriString)
                            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                            result.success(bytes)
                        } catch (e: Exception) {
                            result.error("READ_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == Intent.ACTION_SEND || intent.action == Intent.ACTION_SEND_MULTIPLE) {
            pendingShareIntent = intent
        }
    }

    private fun extractShareData(intent: Intent?): Map<String, Any?>? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_SEND -> {
                if (intent.type?.startsWith("text/") == true) {
                    val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return null
                    mapOf(
                        "type" to "text",
                        "text" to text,
                        "uris" to emptyList<String>(),
                        "fileNames" to emptyList<String>(),
                        "mimeType" to intent.type,
                    )
                } else {
                    val uri = getUriExtra(intent) ?: return null
                    val isImage = intent.type?.startsWith("image/") == true
                    mapOf(
                        "type" to if (isImage) "image" else "file",
                        "text" to null,
                        "uris" to listOf(uri.toString()),
                        "fileNames" to listOf(getFileName(uri) ?: "file"),
                        "mimeType" to intent.type,
                    )
                }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val uris = getUriListExtra(intent) ?: return null
                val isImage = intent.type?.startsWith("image/") == true
                mapOf(
                    "type" to if (isImage) "images" else "files",
                    "text" to null,
                    "uris" to uris.map { it.toString() },
                    "fileNames" to uris.map { getFileName(it) ?: "file" },
                    "mimeType" to intent.type,
                )
            }
            else -> null
        }
    }

    @Suppress("DEPRECATION")
    private fun getUriExtra(intent: Intent): Uri? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
    }

    @Suppress("DEPRECATION")
    private fun getUriListExtra(intent: Intent): ArrayList<Uri>? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
        }
    }

    private fun getFileName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (cursor.moveToFirst() && nameIndex >= 0) cursor.getString(nameIndex) else null
            }
        } catch (_: Exception) {
            null
        }
    }
}
