package com.kamilloo.mylibrary

import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

class BackupArchiveTest {
    @get:Rule val temp = TemporaryFolder()
    private val database = "database/my_library.db"
    private val cover = "covers/test.jpg"
    private val manifest = "manifest.json"
    private val bytes = "Zażółć gęślą jaźń".toByteArray()

    private fun archive(): File {
        val root = temp.newFolder()
        for (path in listOf(database, cover)) {
            File(root, path).apply {
                parentFile!!.mkdirs()
                writeBytes(bytes)
            }
        }
        return temp.newFile().also { BackupArchive.pack(root, it, 8) }
    }

    @Test fun portableInventoryAndHashes() {
        val archive = archive()
        ZipFile(archive).use { zip ->
            val metadata = JSONObject(zip.getInputStream(zip.getEntry(manifest)).bufferedReader().readText())
            assertEquals(1, metadata.getInt("formatVersion"))
            assertEquals(8, metadata.getInt("schemaVersion"))
            assertEquals("com.kamilloo.mylibrary", metadata.getString("applicationId"))
            assertTrue(metadata.getString("createdAtUtc").endsWith("Z"))
            val files = metadata.getJSONArray("files")
            assertEquals(2, files.length())
            val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
                .joinToString("") { "%02x".format(it) }
            for (index in 0 until files.length()) {
                val file = files.getJSONObject(index)
                assertEquals(bytes.size, file.getInt("size"))
                assertEquals(digest, file.getString("sha256"))
            }
        }
        val restored = temp.newFolder()
        BackupArchive.unpack(archive, restored, 8)
        assertArrayEquals(bytes, File(restored, database).readBytes())
        assertArrayEquals(bytes, File(restored, cover).readBytes())
    }

    private fun rewrite(change: (String, ByteArray) -> Pair<String, ByteArray>): File {
        val output = temp.newFile()
        ZipFile(archive()).use { original ->
            ZipOutputStream(output.outputStream()).use { zip ->
                for (entry in original.entries()) {
                    val (path, data) = change(entry.name, original.getInputStream(entry).use { it.readBytes() })
                    zip.putNextEntry(ZipEntry(path))
                    zip.write(data)
                    zip.closeEntry()
                }
            }
        }
        return output
    }

    @Test fun rejectsModifiedChecksumsAndFutureVersions() {
        val modified = rewrite { path, data ->
            path to if (path == database) ByteArray(data.size) else data
        }
        assertThrows(IllegalArgumentException::class.java) {
            BackupArchive.unpack(modified, temp.newFolder(), 8)
        }
        for (versionField in listOf("formatVersion", "schemaVersion")) {
            val future = rewrite { path, data ->
                path to if (path == manifest) {
                    JSONObject(String(data)).put(versionField, 99).toString().toByteArray()
                } else data
            }
            assertThrows(BackupArchive.FutureVersion::class.java) {
                BackupArchive.unpack(future, temp.newFolder(), 8)
            }
        }
    }

    @Test fun rejectsTraversalAndDuplicateManifestPaths() {
        val traversal = rewrite { path, data ->
            (if (path == cover) "covers/../../bad.jpg" else path) to data
        }
        val output = temp.newFolder()
        assertThrows(IllegalArgumentException::class.java) {
            BackupArchive.unpack(traversal, output, 8)
        }
        val duplicate = rewrite { path, data ->
            path to if (path == manifest) {
                val metadata = JSONObject(String(data))
                val entries = metadata.getJSONArray("files")
                entries.put(1, entries.getJSONObject(0))
                metadata.toString().toByteArray()
            } else data
        }
        assertThrows(IllegalArgumentException::class.java) {
            BackupArchive.unpack(duplicate, output, 8)
        }
        assertTrue(output.list()!!.isEmpty())
    }

    @Test fun rejectsInvalidTruncatedAndOversizedInput() {
        val invalid = temp.newFile().apply { writeText("invalid") }
        val truncated = archive()
        val oversized = temp.newFile()
        RandomAccessFile(truncated, "rw").use { it.setLength(it.length() - 12) }
        RandomAccessFile(oversized, "rw").use { it.setLength(BackupArchive.MAX_BYTES + 1) }
        for (file in listOf(invalid, truncated, oversized)) {
            assertThrows(Exception::class.java) {
                BackupArchive.unpack(file, temp.newFolder(), 8)
            }
        }
    }
}
