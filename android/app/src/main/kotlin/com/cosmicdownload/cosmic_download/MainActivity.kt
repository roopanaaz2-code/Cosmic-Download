package com.cosmicdownload.cosmic_download

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "cosmic_download/storage"
    private val permissionRequestCode = 804
    private var pendingSave: Triple<String, String, String>? = null
    private var pendingResult: MethodChannel.Result? = null

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
                    saveLegacy(source, name, result)
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
    }

    private fun saveWithMediaStore(source: String, name: String, mime: String, result: MethodChannel.Result) {
        var uri: Uri? = null
        try {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/Cosmic Download")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Android could not create the Downloads file.")
            contentResolver.openOutputStream(uri, "w").use { output ->
                if (output == null) throw IllegalStateException("Could not open the Downloads destination.")
                FileInputStream(File(source)).use { input -> input.copyTo(output) }
                output.flush()
            }
            val ready = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
            contentResolver.update(uri, ready, null, null)
            result.success("Downloads/Cosmic Download/$name")
        } catch (error: Exception) {
            uri?.let { contentResolver.delete(it, null, null) }
            result.error("SAVE_FAILED", error.message ?: "Could not save to Downloads.", null)
        }
    }

    private fun saveLegacy(source: String, name: String, result: MethodChannel.Result) {
        try {
            val folder = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                "Cosmic Download"
            )
            if (!folder.exists() && !folder.mkdirs()) {
                throw IllegalStateException("Could not create the Downloads folder.")
            }
            val destination = File(folder, name)
            FileInputStream(File(source)).use { input ->
                FileOutputStream(destination).use { output -> input.copyTo(output) }
            }
            MediaScannerConnection.scanFile(this, arrayOf(destination.absolutePath), null, null)
            result.success("Downloads/Cosmic Download/$name")
        } catch (error: Exception) {
            result.error("SAVE_FAILED", error.message ?: "Could not save to Downloads.", null)
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
            saveLegacy(args.first, args.second, result)
        } else {
            result.error("STORAGE_PERMISSION_DENIED", "Storage permission is required to save into Downloads.", null)
        }
    }
}
