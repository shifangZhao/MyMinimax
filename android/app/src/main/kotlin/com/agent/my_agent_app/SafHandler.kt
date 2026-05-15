package com.agent.my_agent_app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.util.Base64
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.MethodChannel
import java.io.FileOutputStream

class SafHandler(private val context: Context) {
    private var pickResult: MethodChannel.Result? = null

    fun launchPicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        (context as? android.app.Activity)?.startActivityForResult(intent, SAF_PICK_REQUEST_CODE)
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == SAF_PICK_REQUEST_CODE) {
            val uri = data?.data
            pickResult?.success(uri?.toString())
            pickResult = null
        }
    }

    fun handle(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickDirectory" -> {
                pickResult = result
                launchPicker()
            }
            "persistUriPermission" -> {
                val uriStr = call.argument<String>("uri") ?: ""
                handlePersistUriPermission(uriStr, result)
            }
            "createDirectory" -> {
                val treeUri = call.argument<String>("treeUri") ?: ""
                val path = call.argument<String>("path") ?: ""
                handleCreateDirectory(treeUri, path, result)
            }
            "readFile" -> {
                val treeUri = call.argument<String>("treeUri") ?: ""
                val path = call.argument<String>("path") ?: ""
                handleReadFile(treeUri, path, result)
            }
            "writeFile" -> {
                val treeUri = call.argument<String>("treeUri") ?: ""
                val path = call.argument<String>("path") ?: ""
                val content = call.argument<String>("content") ?: ""
                handleWriteFile(treeUri, path, content, result)
            }
            "deleteFile" -> {
                val treeUri = call.argument<String>("treeUri") ?: ""
                val path = call.argument<String>("path") ?: ""
                handleDeleteFile(treeUri, path, result)
            }
            "listFiles" -> {
                val treeUri = call.argument<String>("treeUri") ?: ""
                val path = call.argument<String>("path") ?: ""
                handleListFiles(treeUri, path, result)
            }
            "readFileBytes" -> {
                val treeUri = call.argument<String>("treeUri") ?: ""
                val path = call.argument<String>("path") ?: ""
                handleReadFileBytes(treeUri, path, result)
            }
            "writeFileBytes" -> {
                val treeUri = call.argument<String>("treeUri") ?: ""
                val path = call.argument<String>("path") ?: ""
                val content = call.argument<String>("content") ?: ""
                handleWriteFileBytes(treeUri, path, content, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun handlePersistUriPermission(uriStr: String, result: MethodChannel.Result) {
        try {
            val uri = Uri.parse(uriStr)
            val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            context.contentResolver.takePersistableUriPermission(uri, flags)
            result.success(true)
        } catch (e: Exception) {
            Log.e("SAF", "persistUriPermission failed", e)
            result.success(false)
        }
    }

    private fun handleCreateDirectory(treeUriStr: String, relativePath: String, result: MethodChannel.Result) {
        try {
            val treeUri = Uri.parse(treeUriStr)
            val segments = relativePath.replace("\\", "/").split("/").filter { it.isNotEmpty() }
            if (segments.isEmpty()) {
                result.error("INVALID_PATH", "路径不能为空", null)
                return
            }
            var currentDir = DocumentFile.fromTreeUri(context, treeUri)
            if (currentDir == null || !currentDir.exists()) {
                result.error("NOT_FOUND", "根目录不存在", null)
                return
            }
            for (name in segments) {
                var subDir = currentDir!!.findFile(name)
                if (subDir == null) subDir = findChildByName(currentDir!!, name)
                if (subDir == null) subDir = currentDir!!.createDirectory(name)
                if (subDir == null || !subDir.isDirectory) {
                    result.error("CREATE_DIR_ERROR", "无法创建目录: $name", null)
                    return
                }
                currentDir = subDir
            }
            result.success(true)
        } catch (e: Exception) {
            Log.e("SAF", "createDirectory failed: $relativePath", e)
            result.error("CREATE_DIR_ERROR", e.message, null)
        }
    }

    private fun handleReadFile(treeUriStr: String, relativePath: String, result: MethodChannel.Result) {
        try {
            val docFile = findDocumentFile(treeUriStr, relativePath, isDirectory = false)
            if (docFile == null) {
                result.error("NOT_FOUND", "文件不存在: $relativePath", null)
                return
            }
            val inputStream = context.contentResolver.openInputStream(docFile.uri)
            if (inputStream == null) {
                result.error("READ_ERROR", "无法打开文件: $relativePath", null)
                return
            }
            val content = inputStream.bufferedReader().use { it.readText() }
            result.success(content)
        } catch (e: Exception) {
            Log.e("SAF", "readFile failed: $relativePath", e)
            result.error("READ_ERROR", e.message, null)
        }
    }

    private fun handleReadFileBytes(treeUriStr: String, relativePath: String, result: MethodChannel.Result) {
        try {
            val docFile = findDocumentFile(treeUriStr, relativePath, isDirectory = false)
            if (docFile == null) {
                result.error("NOT_FOUND", "文件不存在: $relativePath", null)
                return
            }
            val inputStream = context.contentResolver.openInputStream(docFile.uri)
            if (inputStream == null) {
                result.error("READ_ERROR", "无法打开文件: $relativePath", null)
                return
            }
            val bytes = inputStream.use { it.readBytes() }
            result.success(Base64.encodeToString(bytes, Base64.NO_WRAP))
        } catch (e: Exception) {
            Log.e("SAF", "readFileBytes failed: $relativePath", e)
            result.error("READ_ERROR", e.message, null)
        }
    }

    private fun handleWriteFileBytes(treeUriStr: String, relativePath: String, base64Content: String, result: MethodChannel.Result) {
        try {
            val bytes = Base64.decode(base64Content, Base64.NO_WRAP)
            val (dir, fileName) = navigateToParent(treeUriStr, relativePath, result) ?: return
            writeBytesToFile(dir!!, fileName, bytes, result)
        } catch (e: Exception) {
            Log.e("SAF", "writeFileBytes failed: $relativePath", e)
            result.error("WRITE_ERROR", e.message, null)
        }
    }

    private fun handleWriteFile(treeUriStr: String, relativePath: String, content: String, result: MethodChannel.Result) {
        try {
            val (dir, fileName) = navigateToParent(treeUriStr, relativePath, result) ?: return
            writeTextToFile(dir!!, fileName, content, result)
        } catch (e: Exception) {
            Log.e("SAF", "writeFile failed: $relativePath", e)
            result.error("WRITE_ERROR", e.message, null)
        }
    }

    private fun handleDeleteFile(treeUriStr: String, relativePath: String, result: MethodChannel.Result) {
        try {
            val docFile = findDocumentFile(treeUriStr, relativePath, isDirectory = null)
            if (docFile == null) {
                result.error("NOT_FOUND", "文件或目录不存在: $relativePath", null)
                return
            }
            result.success(docFile.delete())
        } catch (e: Exception) {
            Log.e("SAF", "deleteFile failed: $relativePath", e)
            result.error("DELETE_ERROR", e.message, null)
        }
    }

    private fun handleListFiles(treeUriStr: String, relativePath: String, result: MethodChannel.Result) {
        try {
            val treeUri = Uri.parse(treeUriStr)
            val dir = if (relativePath.isEmpty()) {
                DocumentFile.fromTreeUri(context, treeUri)
            } else {
                findDocumentFile(treeUriStr, relativePath, isDirectory = true)
            }
            if (dir == null || !dir.isDirectory || !dir.exists()) {
                result.error("NOT_FOUND", "目录不存在: $relativePath", null)
                return
            }
            val files = dir.listFiles().map { doc ->
                var lastModified = 0L
                try { lastModified = doc.lastModified() } catch (_: Exception) {}
                if (lastModified == 0L) {
                    try {
                        val path = contentUriToFilePath(doc.uri)
                        if (path != null) {
                            val file = java.io.File(path)
                            if (file.exists()) lastModified = file.lastModified()
                        }
                    } catch (_: Exception) {}
                }
                mapOf(
                    "name" to (doc.name ?: ""),
                    "uri" to doc.uri.toString(),
                    "isDirectory" to doc.isDirectory,
                    "size" to doc.length(),
                    "lastModified" to lastModified,
                )
            }
            result.success(files)
        } catch (e: Exception) {
            Log.e("SAF", "listFiles failed: $relativePath", e)
            result.error("LIST_ERROR", e.message, null)
        }
    }

    // ── helpers ──

    private data class NavResult(val dir: DocumentFile?, val fileName: String)

    private fun navigateToParent(treeUriStr: String, relativePath: String, result: MethodChannel.Result): NavResult? {
        val treeUri = Uri.parse(treeUriStr)
        val segments = relativePath.replace("\\", "/").split("/").filter { it.isNotEmpty() }
        if (segments.isEmpty()) {
            result.error("INVALID_PATH", "路径不能为空", null)
            return null
        }
        var currentDir = DocumentFile.fromTreeUri(context, treeUri)
        if (currentDir == null || !currentDir.exists()) {
            result.error("NOT_FOUND", "根目录不存在", null)
            return null
        }
        for (i in 0 until segments.size - 1) {
            val dirName = segments[i]
            var subDir = currentDir!!.findFile(dirName)
            if (subDir == null) subDir = findChildByName(currentDir!!, dirName)
            if (subDir == null || !subDir.isDirectory) subDir = currentDir!!.createDirectory(dirName)
            if (subDir == null) {
                result.error("CREATE_DIR_ERROR", "无法创建目录: $dirName", null)
                return null
            }
            currentDir = subDir
        }
        return NavResult(currentDir, segments.last())
    }

    private fun writeTextToFile(dir: DocumentFile, fileName: String, content: String, result: MethodChannel.Result) {
        var existingFile = dir.findFile(fileName)
        if (existingFile == null) {
            existingFile = findChildByName(dir, fileName)
        }
        if (existingFile != null && !existingFile.isDirectory) {
            val outputStream = context.contentResolver.openOutputStream(existingFile.uri, "w")
            if (outputStream != null) {
                outputStream.bufferedWriter().use { it.write(content) }
                result.success(existingFile.uri.toString())
            } else {
                result.error("WRITE_ERROR", "无法打开文件写入流", null)
            }
        } else {
            val mimeType = getMimeType(fileName)
            val newFile = dir.createFile(mimeType, fileName)
            if (newFile != null) {
                val outputStream = context.contentResolver.openOutputStream(newFile.uri)
                if (outputStream != null) {
                    outputStream.bufferedWriter().use { it.write(content) }
                    result.success(newFile.uri.toString())
                } else {
                    result.error("WRITE_ERROR", "无法打开新文件写入流", null)
                }
            } else {
                result.error("CREATE_ERROR", "无法创建文件: $fileName", null)
            }
        }
    }

    private fun writeBytesToFile(dir: DocumentFile, fileName: String, bytes: ByteArray, result: MethodChannel.Result) {
        var existingFile = dir.findFile(fileName)
        // If findFile returns null, try listing (SAF provider may cache)
        if (existingFile == null) {
            existingFile = findChildByName(dir, fileName)
        }
        if (existingFile != null && !existingFile.isDirectory) {
            val outputStream = context.contentResolver.openOutputStream(existingFile.uri, "w")
            if (outputStream != null) {
                outputStream.write(bytes)
                outputStream.close()
                result.success(existingFile.uri.toString())
            } else {
                result.error("WRITE_ERROR", "无法打开文件写入流", null)
            }
        } else {
            val mimeType = getMimeType(fileName)
            val newFile = dir.createFile(mimeType, fileName)
            if (newFile != null) {
                val outputStream = context.contentResolver.openOutputStream(newFile.uri)
                if (outputStream != null) {
                    outputStream.write(bytes)
                    outputStream.close()
                    result.success(newFile.uri.toString())
                } else {
                    result.error("WRITE_ERROR", "无法打开新文件写入流", null)
                }
            } else {
                result.error("CREATE_ERROR", "无法创建文件: $fileName", null)
            }
        }
    }

    private fun findDocumentFile(treeUriStr: String, relativePath: String, isDirectory: Boolean?): DocumentFile? {
        val treeUri = Uri.parse(treeUriStr)
        val segments = relativePath.replace("\\", "/").split("/").filter { it.isNotEmpty() }
        if (segments.isEmpty()) return DocumentFile.fromTreeUri(context, treeUri)

        var current = DocumentFile.fromTreeUri(context, treeUri) ?: return null
        for (i in segments.indices) {
            val isLast = i == segments.size - 1
            val name = segments[i]
            // findFile() may return null for recently-created files due to SAF caching
            var found = current.findFile(name)
            if (found == null) found = findChildByName(current, name)
            if (found == null) return null
            if (isLast) {
                if (isDirectory == true && !found.isDirectory) return null
                if (isDirectory == false && found.isDirectory) return null
                return found
            } else {
                if (!found.isDirectory) return null
                current = found
            }
        }
        return current
    }

    /** Fallback: list children and match by name, case-insensitive.
     *  Work arounds DocumentFile.findFile() caching issues on some SAF providers. */
    private fun findChildByName(dir: DocumentFile, name: String): DocumentFile? {
        return try {
            dir.listFiles().find { it.name?.equals(name, ignoreCase = true) == true }
        } catch (_: Exception) {
            null
        }
    }

    private fun contentUriToFilePath(uri: Uri): String? {
        if (uri.authority != "com.android.externalstorage.documents") return null
        try {
            val docId = DocumentsContract.getDocumentId(uri)
            val parts = docId.split(":")
            if (parts.size < 2) return null
            val root = if (parts[0] == "primary") {
                "${android.os.Environment.getExternalStorageDirectory().path}/"
            } else {
                "/storage/${parts[0]}/"
            }
            return root + parts[1]
        } catch (_: Exception) {
            return null
        }
    }

    private fun getMimeType(fileName: String): String {
        return when (fileName.substringAfterLast('.', "").lowercase()) {
            "txt" -> "text/plain"
            "html", "htm" -> "text/html"
            "css" -> "text/css"
            "js" -> "application/javascript"
            "json" -> "application/json"
            "xml" -> "application/xml"
            "pdf" -> "application/pdf"
            "png" -> "image/png"
            "jpg", "jpeg" -> "image/jpeg"
            "gif" -> "image/gif"
            "svg" -> "image/svg+xml"
            "md" -> "text/markdown"
            "csv" -> "text/csv"
            "docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            "pptx" -> "application/vnd.openxmlformats-officedocument.presentationml.presentation"
            "epub" -> "application/epub+zip"
            else -> "application/octet-stream"
        }
    }

    companion object {
        const val SAF_PICK_REQUEST_CODE = 2001
    }
}
