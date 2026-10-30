package com.billsbayarea.bills_bay_area

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Point
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * The two places the upload screen takes photos from on Android, plus the
 * previews and full reads of what was picked. Photos are named by their
 * content address ("id") and read only when needed: a folder can hold
 * hundreds, too many to copy whole just to show.
 *
 * - "Photos on this device" is Android's folder browser, opened at the top of
 *   the phone's storage. Every photo in the chosen folder and its subfolders
 *   comes back, newest first, for the app to show and the user to choose from.
 * - "Photos from the Cloud" is Android's document picker, where Google Drive
 *   is. Drive will not hand a whole folder to an app (its folders show "Can't
 *   use this folder" in the folder browser), so there the photos are chosen in
 *   the picker itself: long-press one, then ⋮ › Select all for a whole folder.
 *   The picker opens in the folder of the last Drive photo picked; before
 *   the first, wherever this app last was, with Drive under ☰.
 */
class PhotoPicker(
    private val activity: Activity,
    private val readOriginal: (Uri) -> ByteArray?,
) : MethodChannel.MethodCallHandler {
    private var pending: MethodChannel.Result? = null
    private var limit = 0

    // Previews are asked for a screenful at a time; a few at once keeps them
    // coming without starting a thread apiece.
    private val workers = Executors.newFixedThreadPool(4)

    private val prefs
        get() = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickDeviceFolder" -> launch(call, result, deviceFolderIntent(), DEVICE_FOLDER)
            "pickCloudPhotos" -> launch(call, result, cloudPhotosIntent(), CLOUD_PHOTOS)
            "thumbnail" -> work(result) {
                thumbnail(call.uri(), call.argument<Int>("size") ?: 240)
            }
            "read" -> work(result) { read(call.uri()) }
            else -> result.notImplemented()
        }
    }

    /** Takes a picker's answer; false if the request was not one of these. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != DEVICE_FOLDER && requestCode != CLOUD_PHOTOS) return false
        val result = pending ?: return true
        pending = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(null)
            return true
        }
        val limit = limit
        work(result) {
            if (requestCode == DEVICE_FOLDER) {
                data.data?.let { listFolder(it, limit) }
            } else {
                describePicked(data, limit)
            }
        }
        return true
    }

    private fun launch(call: MethodCall, result: MethodChannel.Result, intent: Intent, code: Int) {
        if (pending != null) {
            // A picker is already open; don't stack another.
            result.success(null)
            return
        }
        try {
            activity.startActivityForResult(intent, code)
        } catch (e: ActivityNotFoundException) {
            result.error("picker", "No picker on this phone", null)
            return
        }
        pending = result
        limit = call.argument<Int>("limit") ?: 200
    }

    private fun deviceFolderIntent() = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        .putExtra(
            DocumentsContract.EXTRA_INITIAL_URI,
            DocumentsContract.buildDocumentUri(EXTERNAL_STORAGE, "primary:"),
        )

    private fun cloudPhotosIntent(): Intent {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("image/*")
            .putExtra(Intent.EXTRA_MIME_TYPES, IMAGE_TYPES.toTypedArray())
            .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        // Given a photo's address, the picker opens the folder it is in. Drive
        // offers no address for its top level (the picker cannot open the one
        // it lists), so until a Drive photo has been picked the picker opens
        // where this app last was, and Drive is under ☰.
        prefs.getString(LAST_DRIVE_PHOTO, null)?.let {
            intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI, Uri.parse(it))
        }
        return intent
    }

    /**
     * The photos under [tree], newest first, at most [limit]: the chosen
     * folder's and its subfolders'.
     */
    private fun listFolder(tree: Uri, limit: Int): List<Map<String, Any>> {
        data class Found(val id: String, val name: String, val modified: Long)

        val found = mutableListOf<Found>()
        val folders = ArrayDeque(listOf(DocumentsContract.getTreeDocumentId(tree)))
        while (folders.isNotEmpty()) {
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(
                tree,
                folders.removeFirst(),
            )
            activity.contentResolver.query(
                children,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                    DocumentsContract.Document.COLUMN_LAST_MODIFIED,
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
                        in IMAGE_TYPES -> found.add(
                            Found(id, name, if (cursor.isNull(3)) 0 else cursor.getLong(3)),
                        )
                    }
                }
            }
        }
        return found.sortedByDescending { it.modified }.take(limit).map {
            mapOf(
                "id" to DocumentsContract.buildDocumentUriUsingTree(tree, it.id).toString(),
                "name" to it.name,
            )
        }
    }

    /** The photos ticked in the document picker, as id and name. */
    private fun describePicked(data: Intent, limit: Int): List<Map<String, Any>> {
        val uris = data.clipData?.let { clip -> (0 until clip.itemCount).map { clip.getItemAt(it).uri } }
            ?: listOfNotNull(data.data)
        uris.firstOrNull { it.authority == DRIVE }?.let {
            prefs.edit().putString(LAST_DRIVE_PHOTO, it.toString()).apply()
        }
        return uris.take(limit).map { mapOf("id" to it.toString(), "name" to displayName(it)) }
    }

    private fun displayName(uri: Uri): String {
        activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0)?.let { return it } }
        return uri.lastPathSegment ?: "photo"
    }

    /**
     * A JPEG about [size] pixels across: the provider's own thumbnail where it
     * has one (the phone's storage and Drive both do), else the photo itself
     * decoded small.
     */
    private fun thumbnail(uri: Uri, size: Int): ByteArray? {
        val bitmap = try {
            DocumentsContract.getDocumentThumbnail(
                activity.contentResolver,
                uri,
                Point(size, size),
                null,
            )
        } catch (e: Exception) {
            null
        } ?: decodeSmall(uri, size) ?: return null
        return ByteArrayOutputStream().use {
            bitmap.compress(Bitmap.CompressFormat.JPEG, 80, it)
            it.toByteArray()
        }
    }

    private fun decodeSmall(uri: Uri, size: Int): Bitmap? {
        val resolver = activity.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= size && bounds.outHeight / (sample * 2) >= size) {
            sample *= 2
        }
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        return resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) }
    }

    /** The photo in full: the original where Android allows, so its GPS stays. */
    private fun read(uri: Uri): ByteArray? {
        val original = try {
            readOriginal(uri)
        } catch (e: Exception) {
            null
        }
        return original ?: activity.contentResolver.openInputStream(uri)?.use { it.readBytes() }
    }

    /**
     * Runs [task] off the main thread and answers with what it returns, or
     * with an error if it throws: a folder that cannot be read must not look
     * like no folder chosen.
     */
    private fun work(result: MethodChannel.Result, task: () -> Any?) {
        workers.execute {
            try {
                val value = task()
                activity.runOnUiThread { result.success(value) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("picker", e.message, null) }
            }
        }
    }

    private fun MethodCall.uri(): Uri = Uri.parse(argument<String>("id"))

    companion object {
        const val CHANNEL = "bills_bay_area/photo_picker"
        private const val DEVICE_FOLDER = 4128
        private const val CLOUD_PHOTOS = 4129
        private const val EXTERNAL_STORAGE = "com.android.externalstorage.documents"
        private const val DRIVE = "com.google.android.apps.docs.storage"
        private const val PREFS = "photo_picker"
        private const val LAST_DRIVE_PHOTO = "last_drive_photo"

        /** The photo types the app takes, HEIC from iPhones too. */
        private val IMAGE_TYPES = setOf(
            "image/jpeg",
            "image/png",
            "image/webp",
            "image/heic",
            "image/heif",
        )
    }
}
