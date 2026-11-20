package com.cosmicdownload.cosmic_download

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "cosmic_download/storage"
    private val diagnosticsChannelName = "cosmic_download/diagnostics"
    private val permissionRequestCode = 804
    private var pendingSave: Triple<String, String, String>? = null
    private var pendingResult: MethodChannel.Result? = null
    private val diagnosticsPreferences by lazy {
        getSharedPreferences("cosmic_download_diagnostics", MODE_PRIVATE)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        installDiagnosticExceptionHandler()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveToDownloads") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val source = call.argument<String>("sourcePath")
                val name = call.argument<String>("fileName")
                val mime = call.argument<String>("mimeType") ?: "application/octet-stream"
                if (source.isNullOrBlank() || name.isNullOrBlank() || !File(source).isFile) {
                    result.error("INVALID_FILE", "The downloaded file is missing.", null)
                    return@setMethodCallHandler
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    saveWithMediaStore(source, name, mime, result)
                } else if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE)
                    == PackageManager.PERMISSION_GRANTED) {
                    saveLegacy(source, name, mime, result)
                } else {
                    pendingSave = Triple(source, name, mime)
                    pendingResult = result
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                        permissionRequestCode
                    )
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, diagnosticsChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "recordStage" -> {
                        val stage = call.argument<String>("stage")
                        if (stage.isNullOrBlank()) {
                            result.error("INVALID_STAGE", "Diagnostic stage is empty.", null)
                        } else {
                            val saved = diagnosticsPreferences.edit()
                                .putString("stage", stage)
                                .putLong("stageTime", System.currentTimeMillis())
                                .commit()
                            if (saved) result.success(null)
                            else result.error("DIAGNOSTIC_WRITE_FAILED", "Could not save diagnostic stage.", null)
                        }
                    }
                    "clearStage" -> {
                        diagnosticsPreferences.edit().remove("stage").remove("stageTime").commit()
                        result.success(null)
                    }
                    "consumePreviousFailure" -> {
                        val failure = diagnosticsPreferences.getString("crash", null)
                        val failureStage = diagnosticsPreferences.getString("crashStage", null)
                        val activeStage = diagnosticsPreferences.getString("stage", null)
                        val snapshot = if (failure != null || failureStage != null || activeStage != null) {
                            mapOf(
                                "stage" to (failureStage ?: activeStage ?: "unknown"),
                                "exception" to (failure ?: ""),
                                "manufacturer" to Build.MANUFACTURER,
                                "model" to Build.MODEL,
                                "androidVersion" to Build.VERSION.RELEASE,
                                "sdk" to Build.VERSION.SDK_INT.toString(),
                            )
                        } else null
                        diagnosticsPreferences.edit()
                            .remove("crash")
                            .remove("crashStage")
                            .remove("stage")
                            .remove("stageTime")
                            .commit()
                        result.success(snapshot)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun installDiagnosticExceptionHandler() {
        synchronized(MainActivity::class.java) {
            if (diagnosticHandlerInstalled) return
            val previousHandler = Thread.getDefaultUncaughtExceptionHandler()
            Thread.setDefaultUncaughtExceptionHandler { thread, error ->
                try {
                    val stage = diagnosticsPreferences.getString("stage", "unknown")
                    val stack = Log.getStackTraceString(error).take(16000)
                    diagnosticsPreferences.edit()
                        .putString("crash", stack)
                        .putString("crashStage", stage)
                        .commit()
                } catch (_: Throwable) {
                    // Diagnostics must never prevent Android's original crash handler.
                }
                previousHandler?.uncaughtException(thread, error)
            }
            diagnosticHandlerInstalled = true
        }
    }

    companion object {
        @Volatile
        private var diagnosticHandlerInstalled = false
    }

    private fun saveWithMediaStore(
        source: String,
        name: String,
        mime: String,
        result: MethodChannel.Result
    ) {
        var uri: Uri? = null
        try {
            val collection = when {
                mime.startsWith("video/") ->
                    MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                mime.startsWith("audio/") ->
                    MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                else -> MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL)
            }
            val relativeFolder = when {
                mime.startsWith("video/") -> "${Environment.DIRECTORY_MOVIES}/Cosmic Download"
                mime.startsWith("audio/") -> "${Environment.DIRECTORY_MUSIC}/Cosmic Download"
                else -> "${Environment.DIRECTORY_DOWNLOADS}/Cosmic Download"
            }
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, relativeFolder)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            uri = contentResolver.insert(collection, values)
                ?: throw IllegalStateException("Android could not create the media-library entry.")
            contentResolver.openOutputStream(uri, "w").use { output ->
                if (output == null) throw IllegalStateException("Could not open the phone storage destination.")
                FileInputStream(File(source)).use { input -> input.copyTo(output) }
                output.flush()
            }
            val ready = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            contentResolver.update(uri, ready, null, null)
            result.success("$relativeFolder/$name")
        } catch (error: Exception) {
            uri?.let { contentResolver.delete(it, null, null) }
            result.error("SAVE_FAILED", error.message ?: "Could not save media to the phone.", null)
        }
    }

    private fun saveLegacy(
        source: String,
        name: String,
        mime: String,
        result: MethodChannel.Result
    ) {
        try {
            val parent = when {
                mime.startsWith("video/") -> Environment.DIRECTORY_MOVIES
                mime.startsWith("audio/") -> Environment.DIRECTORY_MUSIC
                else -> Environment.DIRECTORY_DOWNLOADS
            }
            val folder = File(
                Environment.getExternalStoragePublicDirectory(parent),
                "Cosmic Download"
            )
            if (!folder.exists() && !folder.mkdirs()) {
                throw IllegalStateException("Could not create the public media folder.")
            }
            val destination = File(folder, name)
            FileInputStream(File(source)).use { input ->
                FileOutputStream(destination).use { output -> input.copyTo(output) }
            }
            MediaScannerConnection.scanFile(
                this,
                arrayOf(destination.absolutePath),
                arrayOf(mime),
                null
            )
            result.success("$parent/Cosmic Download/$name")
        } catch (error: Exception) {
            result.error("SAVE_FAILED", error.message ?: "Could not save media to the phone.", null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequestCode) return
        val args = pendingSave
        val result = pendingResult
        pendingSave = null
        pendingResult = null
        if (args == null || result == null) return
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            saveLegacy(args.first, args.second, args.third, result)
        } else {
            result.error(
                "STORAGE_PERMISSION_DENIED",
                "Storage permission is required to save into Downloads.",
                null
            )
        }
    }
}
