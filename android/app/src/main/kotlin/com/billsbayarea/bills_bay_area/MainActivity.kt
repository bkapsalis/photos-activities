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
    private var pendingFolder: MethodChannel.Result? = null
    private var folderLimit = 0

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FOLDER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFolderImages" ->
                        pickFolderImages(call.argument<Int>("limit") ?: 50, result)
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Lets the user choose one folder in Android's own folder browser, then
     * answers with the photos in it and its subfolders, at most [limit], as
     * name and bytes; null if no folder was chosen.
     *
     * The browser offers folders on the phone; Android 11 and later leave out
     * the top of the storage and the Download folder itself, though folders
     * inside them can be chosen.
     */
    private fun pickFolderImages(limit: Int, result: MethodChannel.Result) {
        if (pendingFolder != null) {
            // A folder browser is already open; don't stack another.
            result.success(null)
            return
        }
        pendingFolder = result
        folderLimit = limit
        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), FOLDER_REQUEST_CODE)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != FOLDER_REQUEST_CODE) return
        val result = pendingFolder ?: return
        pendingFolder = null
        val tree = data?.data
        if (resultCode != RESULT_OK || tree == null) {
            result.success(null)
            return
        }
        // Off the main thread: a folder of photos runs to tens of megabytes.
        Thread {
            val images = try {
                readFolderImages(tree, folderLimit)
            } catch (e: Exception) {
                null
            }
            runOnUiThread {
                if (images == null) {
                    result.error("folder", "The folder could not be read", null)
                } else {
                    result.success(images)
                }
            }
        }.start()
    }

    /**
     * The photos under [tree], the chosen folder's own first, each folder's
     * in name order, then its subfolders' in turn.
     */
    private fun readFolderImages(tree: Uri, limit: Int): List<Map<String, Any>> {
        val images = mutableListOf<Map<String, Any>>()
        val folders = ArrayDeque(listOf(DocumentsContract.getTreeDocumentId(tree)))
        while (folders.isNotEmpty() && images.size < limit) {
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(
                tree,
                folders.removeFirst(),
            )
            val files = mutableListOf<Pair<String, String>>()
            contentResolver.query(
                children,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                ),
                null,
                null,
                null,
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val id = cursor.getString(0)
                    val name = cursor.getString(1) ?: continue
                    when (cursor.getString(2)) {
                        DocumentsContract.Document.MIME_TYPE_DIR -> folders.add(id)
                        in IMAGE_TYPES -> files.add(id to name)
                    }
                }
            }
            for ((id, name) in files.sortedBy { it.second.lowercase() }) {
                if (images.size >= limit) break
                val uri = DocumentsContract.buildDocumentUriUsingTree(tree, id)
                // The original where Android allows it, so the GPS survives.
                val bytes = try {
                    readOriginalBytes(uri)
                } catch (e: Exception) {
                    null
                } ?: try {
                    contentResolver.openInputStream(uri)?.use { it.readBytes() }
                } catch (e: Exception) {
                    // One unreadable photo should not sink the rest.
                    null
                }
                if (bytes != null && bytes.isNotEmpty()) {
                    images.add(mapOf("name" to name, "bytes" to bytes))
                }
            }
        }
        return images
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
        private const val FOLDER_CHANNEL = "bills_bay_area/folder_picker"
        private const val REQUEST_CODE = 4127
        private const val FOLDER_REQUEST_CODE = 4128

        /** The photo types the other pickers offer, HEIC from iPhones too. */
        private val IMAGE_TYPES = setOf(
            "image/jpeg",
            "image/png",
            "image/webp",
            "image/heic",
            "image/heif",
        )
    }
}
