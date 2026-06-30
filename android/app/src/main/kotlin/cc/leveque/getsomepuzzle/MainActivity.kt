package cc.leveque.getsomepuzzle

import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "getsomepuzzle/saf"
    private var pendingPickDirectory: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "listFiles" -> {
                        val uri = call.argument<String>("uri")
                        if (uri == null) {
                            result.error("NO_URI", "uri required", null)
                            return@setMethodCallHandler
                        }
                        val prefix = call.argument<String>("prefix") ?: ""
                        result.success(listFiles(uri, prefix))
                    }
                    "readFile" -> {
                        val uri = call.argument<String>("uri")
                        if (uri == null) {
                            result.error("NO_URI", "uri required", null)
                            return@setMethodCallHandler
                        }
                        val fileName = call.argument<String>("fileName")
                        if (fileName == null) {
                            result.error("NO_FILE", "fileName required", null)
                            return@setMethodCallHandler
                        }
                        result.success(readFile(uri, fileName))
                    }
                    "writeFile" -> {
                        val uri = call.argument<String>("uri")
                        if (uri == null) {
                            result.error("NO_URI", "uri required", null)
                            return@setMethodCallHandler
                        }
                        val fileName = call.argument<String>("fileName")
                        if (fileName == null) {
                            result.error("NO_FILE", "fileName required", null)
                            return@setMethodCallHandler
                        }
                        val content = call.argument<String>("content") ?: ""
                        writeFile(uri, fileName, content)
                        result.success(null)
                    }
                    "deleteFiles" -> {
                        val uri = call.argument<String>("uri")
                        if (uri == null) {
                            result.error("NO_URI", "uri required", null)
                            return@setMethodCallHandler
                        }
                        val prefix = call.argument<String>("prefix") ?: ""
                        deleteFiles(uri, prefix)
                        result.success(null)
                    }
                    "pickDirectory" -> {
                        pendingPickDirectory = result
                        startActivityForResult(
                            Intent(Intent.ACTION_OPEN_DOCUMENT_TREE),
                            PICK_DIRECTORY_REQUEST,
                        )
                    }
                    "getDisplayPath" -> {
                        val uriString = call.arguments as? String
                        result.success(
                            if (uriString != null) getDisplayPath(uriString) else null,
                        )
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                if (!e.message.isNullOrEmpty()) {
                    result.error("ERROR", e.message, null)
                } else {
                    result.error("ERROR", "unexpected error", null)
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_DIRECTORY_REQUEST) {
            if (resultCode == RESULT_OK && data?.data != null) {
                val uri = data.data!!
                try {
                    val flags =
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    contentResolver.takePersistableUriPermission(uri, flags)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
                pendingPickDirectory?.success(uri.toString())
            } else {
                pendingPickDirectory?.success(null)
            }
            pendingPickDirectory = null
        }
    }

    private fun listFiles(uri: String, prefix: String): List<String> {
        val treeUri = Uri.parse(uri)
        val childrenUri =
            DocumentsContract.buildChildDocumentsUriUsingTree(
                treeUri,
                DocumentsContract.getTreeDocumentId(treeUri),
            )
        val projection =
            arrayOf(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            )
        val names = mutableListOf<String>()
        contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val name =
                    cursor.getString(
                        cursor.getColumnIndexOrThrow(
                            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                        ),
                    )
                val mime =
                    cursor.getString(
                        cursor.getColumnIndexOrThrow(
                            DocumentsContract.Document.COLUMN_MIME_TYPE,
                        ),
                    )
                if (mime != DocumentsContract.Document.MIME_TYPE_DIR && name.startsWith(prefix)) {
                    names.add(name)
                }
            }
        }
        return names
    }

    private fun readFile(uri: String, fileName: String): String? {
        val docUri = findDocument(uri, fileName) ?: return null
        contentResolver.openInputStream(docUri)?.use { inputStream ->
            return inputStream.bufferedReader().use { it.readText() }
        }
        return null
    }

    private fun writeFile(uri: String, fileName: String, content: String) {
        val treeUri = Uri.parse(uri)
        var docUri = findDocument(uri, fileName)
        if (docUri == null) {
            val docId = DocumentsContract.getTreeDocumentId(treeUri)
            val parentDocUri = DocumentsContract.buildDocumentUriUsingTree(
                treeUri,
                docId,
            )
            docUri =
                DocumentsContract.createDocument(
                    contentResolver,
                    parentDocUri,
                    "text/plain",
                    fileName.removeSuffix(".txt").let { "$it.txt" },
                )
        }
        if (docUri == null) throw Exception("Failed to create document $fileName")
        contentResolver.openOutputStream(docUri)?.use { outputStream ->
            outputStream.write(content.toByteArray(Charsets.UTF_8))
        } ?: throw Exception("Failed to open output stream for $fileName")
    }

    private fun deleteFiles(uri: String, prefix: String) {
        val treeUri = Uri.parse(uri)
        val childrenUri =
            DocumentsContract.buildChildDocumentsUriUsingTree(
                treeUri,
                DocumentsContract.getTreeDocumentId(treeUri),
            )
        val projection =
            arrayOf(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            )
        contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val name =
                    cursor.getString(
                        cursor.getColumnIndexOrThrow(
                            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                        ),
                    )
                val docId =
                    cursor.getString(
                        cursor.getColumnIndexOrThrow(
                            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                        ),
                    )
                val mime =
                    cursor.getString(
                        cursor.getColumnIndexOrThrow(
                            DocumentsContract.Document.COLUMN_MIME_TYPE,
                        ),
                    )
                if (mime != DocumentsContract.Document.MIME_TYPE_DIR && name.startsWith(prefix)) {
                    DocumentsContract.deleteDocument(
                        contentResolver,
                        DocumentsContract.buildDocumentUriUsingTree(treeUri, docId),
                    )
                }
            }
        }
    }

    private fun findDocument(uri: String, fileName: String): Uri? {
        val treeUri = Uri.parse(uri)
        val childrenUri =
            DocumentsContract.buildChildDocumentsUriUsingTree(
                treeUri,
                DocumentsContract.getTreeDocumentId(treeUri),
            )
        val projection =
            arrayOf(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            )
        contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val name =
                    cursor.getString(
                        cursor.getColumnIndexOrThrow(
                            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                        ),
                    )
                val docId =
                    cursor.getString(
                        cursor.getColumnIndexOrThrow(
                            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                        ),
                    )
                val mime =
                    cursor.getString(
                        cursor.getColumnIndexOrThrow(
                            DocumentsContract.Document.COLUMN_MIME_TYPE,
                        ),
                    )
                if (mime != DocumentsContract.Document.MIME_TYPE_DIR && name == fileName) {
                    return DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
                }
            }
        }
        return null
    }

    private fun getDisplayPath(uriString: String): String? {
        val uri = Uri.parse(uriString)
        val docId = DocumentsContract.getTreeDocumentId(uri)
        val path = docId.substringAfter(":")
        return path.ifEmpty { null }
    }

    companion object {
        private const val PICK_DIRECTORY_REQUEST = 0xBE_1E
    }
}
