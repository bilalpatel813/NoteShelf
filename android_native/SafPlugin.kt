// Copy to: android/app/src/main/kotlin/com/booknotes/booknotes/SafPlugin.kt
// (package must match your MainActivity's package; `flutter create --org
// com.booknotes --project-name booknotes` gives com.booknotes.booknotes).
package com.booknotes.booknotes

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.FileNotFoundException
import java.util.concurrent.Executors

class SafException(val code: String, message: String) : Exception(message)

private data class Child(
    val uri: Uri, val name: String, val isDir: Boolean, val size: Long, val modified: Long,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "name" to name, "ref" to uri.toString(), "isDir" to isDir,
        "size" to size, "modified" to modified,
    )
}

class SafPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null
    private var binding: ActivityPluginBinding? = null
    private var pending: MethodChannel.Result? = null
    private var pendingRequest = 0
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private val cr get() = context.contentResolver

    companion object {
        const val REQ_TREE = 7101
        const val REQ_CREATE = 7102
        const val REQ_OPEN = 7103
    }

    // ------------------------------------------------------------ plugin glue
    override fun onAttachedToEngine(b: FlutterPlugin.FlutterPluginBinding) {
        context = b.applicationContext
        channel = MethodChannel(b.binaryMessenger, "com.booknotes/saf")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(b: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(b: ActivityPluginBinding) {
        activity = b.activity; binding = b; b.addActivityResultListener(this)
    }
    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) =
        onAttachedToActivity(b)
    override fun onDetachedFromActivity() {
        binding?.removeActivityResultListener(this); binding = null; activity = null
    }

    // ------------------------------------------------------------ dispatch
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickTree" -> launch(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                )
            }, REQ_TREE, result)
            "pickCreateDocument" -> launch(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = call.argument<String>("mime") ?: "application/octet-stream"
                putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "book.zip")
            }, REQ_CREATE, result)
            "pickOpenDocument" -> launch(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                val mimes = call.argument<List<String>>("mimes")
                if (!mimes.isNullOrEmpty()) putExtra(Intent.EXTRA_MIME_TYPES, mimes.toTypedArray())
            }, REQ_OPEN, result)
            else -> runIo(result) { dispatch(call) }
        }
    }

    private fun launch(intent: Intent, request: Int, result: MethodChannel.Result) {
        val act = activity
        if (act == null) { result.error("IO_ERROR", "No foreground activity", null); return }
        if (pending != null) { result.error("IO_ERROR", "Another picker is open", null); return }
        pending = result; pendingRequest = request
        act.startActivityForResult(intent, request)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_TREE && requestCode != REQ_CREATE && requestCode != REQ_OPEN) return false
        val res = pending ?: return true
        if (requestCode != pendingRequest) return false
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { res.success(null); return true }
        if (requestCode == REQ_TREE) {
            try {
                cr.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            } catch (e: Exception) {
                res.error("PERMISSION_DENIED", "Could not keep access to the folder: ${e.message}", null)
                return true
            }
        }
        res.success(uri.toString())
        return true
    }

    private fun runIo(result: MethodChannel.Result, block: () -> Any?) {
        worker.execute {
            try {
                val v = block()
                main.post { result.success(v) }
            } catch (e: SafException) {
                main.post { result.error(e.code, e.message, null) }
            } catch (e: SecurityException) {
                main.post { result.error("PERMISSION_DENIED", e.message ?: "Permission denied", null) }
            } catch (e: FileNotFoundException) {
                main.post { result.error("NOT_FOUND", e.message ?: "Not found", null) }
            } catch (e: Exception) {
                main.post { result.error("IO_ERROR", e.message ?: e.toString(), null) }
            }
        }
    }

    private fun dispatch(call: MethodCall): Any? {
        val ref = call.argument<String>("ref") ?: throw SafException("INVALID_DATA", "ref missing")
        val name = call.argument<String>("name")
        return when (call.method) {
            "checkAccess" -> { checkAccess(ref, call.argument<Boolean>("write") ?: true); null }
            "displayName" -> displayName(docUri(ref))
            "list" -> children(ref).map { it.toMap() }
            "stat" -> findChild(ref, req(name))?.toMap()
            "readBytes" -> readUri(need(ref, req(name)).uri)
            "writeBytes" -> writeBytes(
                ref, req(name), call.argument<ByteArray>("bytes") ?: ByteArray(0),
                call.argument<Boolean>("overwrite") ?: false
            )
            "delete" -> {
                val c = need(ref, req(name))
                if (!DocumentsContract.deleteDocument(cr, c.uri)) throw SafException("IO_ERROR", "Delete failed")
                null
            }
            "rename" -> rename(ref, req(name), call.argument<String>("newName") ?: throw SafException("INVALID_NAME", "newName missing"))
            "createFolder" -> createFolder(ref, req(name))
            "deleteFolder" -> {
                if (!DocumentsContract.deleteDocument(cr, docUri(ref))) throw SafException("IO_ERROR", "Delete failed")
                null
            }
            "readDocument" -> readUri(Uri.parse(ref))
            "writeDocument" -> writeDocument(Uri.parse(ref), call.argument<ByteArray>("bytes") ?: ByteArray(0), call.argument<Boolean>("overwrite") ?: false)
            "releasePermission" -> { release(ref); null }
            else -> throw SafException("UNSUPPORTED", "Unknown method ${call.method}")
        }
    }

    private fun req(name: String?): String = name ?: throw SafException("INVALID_NAME", "name missing")

    // ------------------------------------------------------------ URIs
    /** Document URI (built with the tree) for a tree ref or a tree-document ref. */
    private fun docUri(ref: String): Uri {
        val uri = Uri.parse(ref)
        val segs = uri.pathSegments
        val docId = if (segs.size >= 4 && segs[2] == "document")
            DocumentsContract.getDocumentId(uri)
        else DocumentsContract.getTreeDocumentId(uri)
        return DocumentsContract.buildDocumentUriUsingTree(uri, docId)
    }

    private fun asTree(ref: String, created: Uri): Uri =
        DocumentsContract.buildDocumentUriUsingTree(Uri.parse(ref), DocumentsContract.getDocumentId(created))

    private fun displayName(doc: Uri): String =
        cr.query(doc, arrayOf(Document.COLUMN_DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        } ?: throw SafException("NOT_FOUND", "Document not found")

    private fun children(ref: String): List<Child> {
        val tree = Uri.parse(ref)
        val parentId = DocumentsContract.getDocumentId(docUri(ref))
        val kids = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
        val cols = arrayOf(
            Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE,
            Document.COLUMN_SIZE, Document.COLUMN_LAST_MODIFIED,
        )
        val out = ArrayList<Child>()
        val cursor = cr.query(kids, cols, null, null, null)
            ?: throw SafException("IO_ERROR", "Provider returned no data")
        cursor.use { c ->
            while (c.moveToNext()) {
                val id = c.getString(0) ?: continue
                val n = c.getString(1) ?: continue
                out.add(Child(
                    DocumentsContract.buildDocumentUriUsingTree(tree, id), n,
                    c.getString(2) == Document.MIME_TYPE_DIR,
                    if (c.isNull(3)) 0L else c.getLong(3),
                    if (c.isNull(4)) 0L else c.getLong(4),
                ))
            }
        }
        return out
    }

    private fun findChild(ref: String, name: String): Child? = children(ref).firstOrNull { it.name == name }
    private fun need(ref: String, name: String): Child =
        findChild(ref, name) ?: throw SafException("NOT_FOUND", "\"$name\" not found")

    // ------------------------------------------------------------ access
    private fun treeIdOf(uri: Uri): String? = try { DocumentsContract.getTreeDocumentId(uri) } catch (e: Exception) { null }

    private fun checkAccess(ref: String, write: Boolean) {
        val uri = Uri.parse(ref)
        val treeId = treeIdOf(uri) ?: throw SafException("INVALID_DATA", "Not a folder URI")
        val grant = cr.persistedUriPermissions.firstOrNull {
            it.uri.authority == uri.authority && treeIdOf(it.uri) == treeId
        } ?: throw SafException("PERMISSION_DENIED", "Access to this folder was revoked or never granted")
        if (!grant.isReadPermission || (write && !grant.isWritePermission))
            throw SafException("PERMISSION_DENIED", "This folder is no longer writable")
        val cols = arrayOf(Document.COLUMN_MIME_TYPE, Document.COLUMN_FLAGS)
        val cursor = cr.query(docUri(ref), cols, null, null, null)
            ?: throw SafException("NOT_FOUND", "Folder not found")
        cursor.use { c ->
            if (!c.moveToFirst()) throw SafException("NOT_FOUND", "Folder not found")
            if (c.getString(0) != Document.MIME_TYPE_DIR) throw SafException("INVALID_DATA", "Not a folder")
            if (write && (c.getInt(1) and Document.FLAG_DIR_SUPPORTS_CREATE) == 0)
                throw SafException("PERMISSION_DENIED", "This location is read-only")
        }
    }

    private fun release(ref: String) {
        val uri = Uri.parse(ref)
        cr.persistedUriPermissions.firstOrNull { it.uri == uri }?.let {
            cr.releasePersistableUriPermission(
                it.uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        }
    }

    // ------------------------------------------------------------ IO
    private fun readUri(uri: Uri): ByteArray =
        cr.openInputStream(uri)?.use { it.readBytes() } ?: throw SafException("IO_ERROR", "Cannot open for reading")

    private fun writeUri(uri: Uri, bytes: ByteArray) {
        // "wt" = write + truncate. SAF has no atomic replace: this is in place.
        val out = cr.openOutputStream(uri, "wt") ?: throw SafException("IO_ERROR", "Cannot open for writing")
        out.use { it.write(bytes); it.flush() }
    }

    private fun mimeFor(name: String): String = when (name.substringAfterLast('.', "").lowercase()) {
        "txt" -> "text/plain"
        "json" -> "application/json"
        "zip" -> "application/zip"
        "png" -> "image/png"
        "jpg", "jpeg" -> "image/jpeg"
        "webp" -> "image/webp"
        "gif" -> "image/gif"
        else -> "application/octet-stream" // never makes providers append an extension
    }

    private fun writeBytes(ref: String, name: String, bytes: ByteArray, overwrite: Boolean): Map<String, Any?> {
        val existing = findChild(ref, name)
        if (existing != null) {
            // createDocument() would silently create "name (1)"; never call it
            // when the name is taken.
            if (existing.isDir || !overwrite) throw SafException("ALREADY_EXISTS", "\"$name\" already exists")
            writeUri(existing.uri, bytes)
            return need(ref, name).toMap()
        }
        var created = DocumentsContract.createDocument(cr, docUri(ref), mimeFor(name), name)
            ?: throw SafException("IO_ERROR", "Provider refused to create the file")
        created = asTree(ref, created)
        if (displayName(created) != name) {
            // Provider renamed it (race on duplicate name, or extension added).
            val renamed = try { DocumentsContract.renameDocument(cr, created, name) } catch (e: Exception) { null }
            if (renamed == null || displayName(asTree(ref, renamed)) != name) {
                try { DocumentsContract.deleteDocument(cr, created) } catch (e: Exception) {}
                throw SafException("ALREADY_EXISTS", "Could not create \"$name\" without renaming")
            }
            created = asTree(ref, renamed)
        }
        try { writeUri(created, bytes) } catch (e: Exception) {
            try { DocumentsContract.deleteDocument(cr, created) } catch (_: Exception) {}
            throw e
        }
        return need(ref, name).toMap()
    }

    private fun rename(ref: String, name: String, newName: String): Any? {
        val src = need(ref, name)
        val clash = findChild(ref, newName)
        if (clash != null && clash.uri != src.uri) throw SafException("ALREADY_EXISTS", "\"$newName\" already exists")
        val out = DocumentsContract.renameDocument(cr, src.uri, newName)
            ?: throw SafException("IO_ERROR", "Rename failed")
        if (displayName(asTree(ref, out)) != newName) throw SafException("IO_ERROR", "Provider changed the new name")
        return null
    }

    private fun createFolder(ref: String, name: String): String {
        if (findChild(ref, name) != null) throw SafException("ALREADY_EXISTS", "\"$name\" already exists")
        val created = DocumentsContract.createDocument(cr, docUri(ref), Document.MIME_TYPE_DIR, name)
            ?: throw SafException("IO_ERROR", "Provider refused to create the folder")
        val tree = asTree(ref, created)
        if (displayName(tree) != name) {
            try { DocumentsContract.deleteDocument(cr, tree) } catch (_: Exception) {}
            throw SafException("ALREADY_EXISTS", "Could not create \"$name\" without renaming")
        }
        return tree.toString()
    }

    private fun writeDocument(uri: Uri, bytes: ByteArray, overwrite: Boolean): Any? {
        if (!overwrite) {
            val size = cr.query(uri, arrayOf(Document.COLUMN_SIZE), null, null, null)?.use {
                if (it.moveToFirst() && !it.isNull(0)) it.getLong(0) else 0L
            } ?: 0L
            if (size > 0) throw SafException("ALREADY_EXISTS", "Target file is not empty")
        }
        writeUri(uri, bytes)
        return null
    }
}
