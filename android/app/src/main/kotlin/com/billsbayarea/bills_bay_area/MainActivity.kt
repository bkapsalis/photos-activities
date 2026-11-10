package com.billsbayarea.bills_bay_area

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private val photoPicker = PhotoPicker(this) { readOriginalBytes(it) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestMediaLocation" -> requestMediaLocation(result)
                    "readOriginal" -> readOriginal(call.argument<String>("uri"), result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PhotoPicker.CHANNEL)
            .setMethodCallHandler(photoPicker)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        photoPicker.onActivityResult(requestCode, resultCode, data)
    }

    /**
     * Asks for ACCESS_MEDIA_LOCATION, which Android requires before it will
     * hand an app a photo with its GPS tags intact. Answers true when the app
     * may read photo locations.
     */
    private fun requestMediaLocation(result: MethodChannel.Result) {
        // Before Android 10 there was no redaction to opt out of.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success(true)
            return
        }
        val permission = Manifest.permission.ACCESS_MEDIA_LOCATION
        if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        if (pendingResult != null) {
            // A request is already on screen; don't stack another.
            result.success(false)
            return
        }
        pendingResult = result
        requestPermissions(arrayOf(permission), REQUEST_CODE)
    }

    /**
     * The picked photo's bytes with its GPS intact, or null if that cannot be
     * had (no permission, not a media item, older Android), in which case the
     * caller keeps the bytes it already has.
     *
     * Android only skips its GPS redaction for an app holding
     * ACCESS_MEDIA_LOCATION that opens the MediaStore item with
     * setRequireOriginal; the content address the picker hands back is a
     * DocumentsProvider one, so it is translated first. Read off the main
     * thread: photos run to several megabytes.
     */
    private fun readOriginal(uriString: String?, result: MethodChannel.Result) {
        if (uriString == null) {
            result.success(null)
            return
        }
        Thread {
            val bytes = try {
                readOriginalBytes(Uri.parse(uriString))
            } catch (e: Exception) {
                null
            }
            runOnUiThread { result.success(bytes) }
        }.start()
    }

    private fun readOriginalBytes(uri: Uri): ByteArray? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        if (checkSelfPermission(Manifest.permission.ACCESS_MEDIA_LOCATION) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return null
        }
        val mediaUri = if (DocumentsContract.isDocumentUri(this, uri)) {
            MediaStore.getMediaUri(this, uri)
        } else {
            uri
        } ?: return null
        val original = MediaStore.setRequireOriginal(mediaUri)
        return contentResolver.openInputStream(original)?.use { it.readBytes() }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_CODE) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingResult?.success(granted)
        pendingResult = null
    }

    companion object {
        private const val CHANNEL = "bills_bay_area/media_location"
        private const val REQUEST_CODE = 4127
    }
}
