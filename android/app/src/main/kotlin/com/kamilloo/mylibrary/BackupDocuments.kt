package com.kamilloo.mylibrary

import android.app.Activity
import android.content.Intent
import android.system.Os
import android.system.OsConstants
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.time.Instant
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

internal class BackupDocuments(private val activity: Activity) {
    private data class Job(
        val work: File,
        val schema: Int,
        val name: String?,
        val result: MethodChannel.Result
    )

    private var active: Job? = null

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "my_library/backup").setMethodCallHandler { call, result ->
            if (call.method == "syncDirectories") {
                val names = call.argument<List<String>>("names")
                Thread {
                    try {
                        val support = activity.filesDir
                        require(names != null &&
                            names.all { it == "covers" || it == "manual_backup" || it.isEmpty() })
                        for (name in names) {
                            val directory = File(support, name)
                            require(directory.isDirectory)
                            val fd = Os.open(directory.path, OsConstants.O_RDONLY, 0)
                            try {
                                Os.fsync(fd)
                            } finally {
                                Os.close(fd)
                            }
                        }
                        activity.runOnUiThread { result.success(null) }
                    } catch (_: Exception) {
                        activity.runOnUiThread { result.error("sync_failure", null, null) }
                    }
                }.start()
                return@setMethodCallHandler
            }
            if (call.method != "export" && call.method != "import") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                check(active == null)
                val directory = File(requireNotNull(call.argument<String>("path"))).canonicalFile
                val root = File(activity.filesDir, "manual_backup").canonicalFile
                require(directory.parentFile == root && directory.name.startsWith("job-"))
                val job = Job(
                    directory,
                    requireNotNull(call.argument<Int>("schema")),
                    if (call.method == "export") requireNotNull(call.argument<String>("name")) else null,
                    result
                )
                active = job
                if (job.name == null) {
                    launchPicker(job)
                } else {
                    background(job) {
                        BackupArchive.pack(File(job.work, "export"), archive(job), job.schema)
                        activity.runOnUiThread { launchPicker(job) }
                    }
                }
            } catch (_: Exception) {
                result.error("document_failure", null, null)
            }
        }
    }

    private fun launchPicker(job: Job) {
        try {
            val intent = Intent(
                if (job.name == null) Intent.ACTION_OPEN_DOCUMENT else Intent.ACTION_CREATE_DOCUMENT
            ).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = if (job.name == null) "*/*" else "application/octet-stream"
                if (job.name != null) putExtra(Intent.EXTRA_TITLE, job.name)
            }
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent, REQUEST)
        } catch (_: Exception) {
            fail(job, "document_failure")
        }
    }

    fun onResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != REQUEST) return false
        val job = active ?: return true
        val uri = data?.data
        if (code != Activity.RESULT_OK) {
            active = null
            job.result.success(false)
        } else if (uri?.scheme != "content") {
            fail(job, "document_failure")
        } else {
            background(job) {
                val resolver = activity.contentResolver
                if (job.name == null) {
                    requireNotNull(resolver.openInputStream(uri)).use { input ->
                        archive(job).outputStream().use { output ->
                            BackupArchive.transfer(input, output, BackupArchive.MAX_BYTES)
                        }
                    }
                    BackupArchive.unpack(archive(job), File(job.work, "import"), job.schema)
                } else {
                    requireNotNull(resolver.openOutputStream(uri, "wt")).use { output ->
                        archive(job).inputStream().use { input -> input.copyTo(output) }
                    }
                }
                activity.runOnUiThread {
                    active = null
                    job.result.success(true)
                }
            }
        }
        return true
    }

    private fun archive(job: Job) = File(job.work, "library.mlbak")

    private fun background(job: Job, action: () -> Unit) {
        Thread {
            try {
                action()
            } catch (_: BackupArchive.FutureVersion) {
                activity.runOnUiThread { fail(job, "future_version") }
            } catch (_: StackOverflowError) {
                // Android's JSON parser recursively parses untrusted manifests.
                activity.runOnUiThread { fail(job, "document_failure") }
            } catch (_: Exception) {
                activity.runOnUiThread { fail(job, "document_failure") }
            }
        }.start()
    }

    private fun fail(job: Job, code: String) {
        active = null
        job.result.error(code, null, null)
    }

    companion object {
        private const val REQUEST = 7241
    }
}

internal object BackupArchive {
    const val MAX_BYTES = 512L * 1024 * 1024
    private const val MAX_ENTRIES = 10002
    private const val MAX_MANIFEST = 4L * 1024 * 1024
    private const val VERSION = 1
    private const val APPLICATION = "com.kamilloo.mylibrary"
    private const val DATABASE = "database/my_library.db"
    private const val MANIFEST = "manifest.json"
    private val coverPath = Regex("covers/[a-zA-Z0-9-]{1,80}\\.jpg")
    private val hash = Regex("[0-9a-f]{64}")

    class FutureVersion : Exception()

    private fun allowed(path: String) = path == DATABASE || coverPath.matches(path)

    fun pack(source: File, archive: File, schema: Int) {
        val contents = source.walkTopDown().filter { it.isFile }.map { file ->
            file.relativeTo(source).invariantSeparatorsPath to file
        }.toList()
        require(contents.size < MAX_ENTRIES && contents.any { it.first == DATABASE })
        var remaining = MAX_BYTES
        val inventory = JSONArray()
        ZipOutputStream(archive.outputStream().buffered()).use { zip ->
            for ((path, file) in contents) {
                require(allowed(path))
                zip.putNextEntry(ZipEntry(path))
                val digest = MessageDigest.getInstance("SHA-256")
                val size = file.inputStream().use { transfer(it, zip, remaining, digest) }
                remaining -= size
                zip.closeEntry()
                inventory.put(JSONObject().put("path", path).put("size", size)
                    .put("sha256", digest.hex()))
            }
            val manifest = JSONObject()
                .put("formatVersion", VERSION)
                .put("createdAtUtc", Instant.now().toString())
                .put("applicationId", APPLICATION)
                .put("schemaVersion", schema)
                .put("files", inventory)
                .toString().toByteArray(Charsets.UTF_8)
            require(manifest.size <= MAX_MANIFEST)
            zip.putNextEntry(ZipEntry(MANIFEST))
            zip.write(manifest)
            zip.closeEntry()
        }
        require(archive.length() <= MAX_BYTES)
    }

    fun unpack(archive: File, target: File, schema: Int) {
        require(archive.length() in 1..MAX_BYTES)
        ZipFile(archive).use { zip ->
            require(zip.size() in 2..MAX_ENTRIES)
            val entries = mutableMapOf<String, ZipEntry>()
            val enumeration = zip.entries()
            while (enumeration.hasMoreElements()) {
                val entry = enumeration.nextElement()
                require(!entry.isDirectory && (entry.name == MANIFEST || allowed(entry.name)))
                require(entries.put(entry.name, entry) == null)
                require(entry.size >= 0 && entry.crc >= 0)
            }
            val manifestEntry = requireNotNull(entries.remove(MANIFEST))
            require(manifestEntry.size in 1..MAX_MANIFEST)
            val crc = CRC32()
            val bytes = java.io.ByteArrayOutputStream()
            require(zip.getInputStream(manifestEntry).use {
                transfer(it, bytes, manifestEntry.size, crc = crc)
            } == manifestEntry.size && crc.value == manifestEntry.crc)
            val manifest = JSONObject(bytes.toString("UTF-8"))
            require(manifest.getString("applicationId") == APPLICATION)
            val format = manifest.get("formatVersion")
            val dbSchema = manifest.get("schemaVersion")
            require(format is Int && dbSchema is Int)
            if (format > VERSION || dbSchema > schema) throw FutureVersion()
            require(format == VERSION && dbSchema == schema)
            val timestamp = manifest.getString("createdAtUtc")
            require(timestamp.endsWith("Z"))
            Instant.parse(timestamp)
            val files = manifest.getJSONArray("files")
            require(files.length() == entries.size && DATABASE in entries)
            val hashes = mutableMapOf<String, String>()
            var remaining = MAX_BYTES
            for (index in 0 until files.length()) {
                val item = files.getJSONObject(index)
                val path = item.getString("path")
                val entry = requireNotNull(entries[path])
                val value = item.get("size")
                require(value is Int || value is Long)
                val size = (value as Number).toLong()
                val expected = item.getString("sha256")
                require(size in 0..remaining && size == entry.size && hash.matches(expected))
                require(hashes.put(path, expected) == null)
                remaining -= size
            }
            // Check local headers as well as the central directory and require
            // both to describe the same unique, allowlisted entries.
            entries[MANIFEST] = manifestEntry
            ZipInputStream(archive.inputStream().buffered()).use { input ->
                while (true) {
                    val local = input.nextEntry ?: break
                    val path = local.name
                    val entry = requireNotNull(entries.remove(path))
                    require(!local.isDirectory && local.method == entry.method)
                    val digest = MessageDigest.getInstance("SHA-256")
                    crc.reset()
                    val actual = if (path == MANIFEST) {
                        val copy = java.io.ByteArrayOutputStream()
                        val count = transfer(input, copy, entry.size, crc = crc)
                        require(copy.toByteArray().contentEquals(bytes.toByteArray()))
                        count
                    } else {
                        val file = File(target, path)
                        require(file.parentFile?.mkdirs() == true || file.parentFile?.isDirectory == true)
                        val count = file.outputStream().use { output ->
                            transfer(input, output, entry.size, digest, crc)
                        }
                        require(digest.hex() == hashes[path])
                        count
                    }
                    require(actual == entry.size && crc.value == entry.crc)
                    input.closeEntry()
                }
            }
            require(entries.isEmpty())
        }
    }

    fun transfer(
        input: InputStream,
        output: OutputStream,
        limit: Long,
        digest: MessageDigest? = null,
        crc: CRC32? = null
    ): Long {
        val buffer = ByteArray(64 * 1024)
        var count = 0L
        while (true) {
            val length = input.read(buffer)
            if (length < 0) break
            count += length
            require(count <= limit)
            digest?.update(buffer, 0, length)
            crc?.update(buffer, 0, length)
            output.write(buffer, 0, length)
        }
        return count
    }

    private fun MessageDigest.hex() = digest().joinToString("") { "%02x".format(it) }
}
