package cc.leveque.getsomepuzzle

import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "getsomepuzzle/saf"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "listFiles" -> {
                    val uri =
                        call.argument<String>("uri")
                            ?: return@setMethodCallHandler
                            result.error("NO_URI", "uri required", null)
                    val prefix = call.argument<String>("prefix") ?: ""
                    result.success(listFiles(uri, prefix))
                }
                "readFile" -> {
                    val uri =
                        call.argument<String>("uri")
                            ?: return@setMethodCallHandler
                            result.error("NO_URI", "uri required", null)
                    val fileName =
                        call.argument<String>("fileName")
                            ?: return@setMethodCallHandler
                            result.error("NO_FILE", "fileName required", null)
                    result.success(readFile(uri, fileName))
                }
                "writeFile" -> {
                    val uri =
                        call.argument<String>("uri")
                            ?: return@setMethodCallHandler
                            result.error("NO_URI", "uri required", null)
                    val fileName =
                        call.argument<String>("fileName")
                            ?: return@setMethodCallHandler
                            result.error("NO_FILE", "fileName required", null)
                    val content = call.argument<String>("content") ?: ""
                    writeFile(uri, fileName, content)
                    result.success(null)
                }
                "deleteFiles" -> {
                    val uri =
                        call.argument<String>("uri")
                            ?: return@setMethodCallHandler
                            result.error("NO_URI", "uri required", null)
                    val prefix = call.argument<String>("prefix") ?: ""
                    deleteFiles(uri, prefix)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
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
            docUri =
                DocumentsContract.createDocument(
                    contentResolver,
                    treeUri,
                    "text/plain",
                    fileName.removeSuffix(".txt").let { "$it.txt" },
                )
        }
        if (docUri != null) {
            contentResolver.openOutputStream(docUri)?.use { outputStream ->
                outputStream.write(content.toByteArray(Charsets.UTF_8))
            }
        }
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
}
