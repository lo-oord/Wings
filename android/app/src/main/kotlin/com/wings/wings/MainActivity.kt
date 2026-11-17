package com.wings.wings

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

/**
 * Bridges finished downloads into the device's public Downloads collection and
 * opens saved files in whichever player the user prefers.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "wings/storage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> {
                        val path = call.argument<String>("path")
                        val fileName = call.argument<String>("fileName")
                        if (path == null || fileName == null) {
                            result.error("invalid_args", "path and fileName are required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(saveToDownloads(path, fileName))
                        } catch (error: Exception) {
                            result.error("save_failed", error.message, null)
                        }
                    }
                    "openFile" -> {
                        val uri = call.argument<String>("uri")
                        if (uri == null) {
                            result.error("invalid_args", "uri is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(openFile(uri))
                        } catch (error: Exception) {
                            result.error("open_failed", error.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveToDownloads(path: String, fileName: String): String? {
        val source = File(path)
        if (!source.exists()) return null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = contentResolver
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(
                    MediaStore.MediaColumns.MIME_TYPE,
                    if (fileName.endsWith(".ts", ignoreCase = true)) {
                        "video/mp2t"
                    } else {
                        "video/mp4"
                    },
                )
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    Environment.DIRECTORY_DOWNLOADS + File.separator + "Wings",
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            val uri = resolver.insert(collection, values) ?: return null
            resolver.openOutputStream(uri)?.use { output ->
                FileInputStream(source).use { input -> input.copyTo(output) }
            }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return uri.toString()
        }

        val directory = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "Wings",
        )
        if (!directory.exists() && !directory.mkdirs()) return null
        val target = File(directory, fileName)
        FileInputStream(source).use { input ->
            FileOutputStream(target).use { output -> input.copyTo(output) }
        }
        return Uri.fromFile(target).toString()
    }

    private fun openFile(uriString: String): Boolean {
        val uri = Uri.parse(uriString)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "video/*")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            startActivity(Intent.createChooser(intent, null))
            true
        } catch (error: Exception) {
            false
        }
    }
}
