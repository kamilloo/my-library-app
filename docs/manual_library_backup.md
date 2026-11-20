# Manual library backup on Android V1

From **Pomoc → Kopia zapasowa**, choose **Eksportuj kopię zapasową**. After the app prepares the file, select a destination in Android's save dialog. Wait for **Kopia zapasowa została zapisana.** Android storage and installed document providers can appear in the picker. Keep a copy somewhere you can access after uninstalling or replacing your phone.

To recover the library, install and open the app, then choose **Pomoc → Kopia zapasowa → Przywróć kopię zapasową**. Select the file. After validation, read the warning and choose **Przywróć dane** to replace the library. Check books, covers, loans and history after success. Export your current library first if you may need it again.

The file is unencrypted and can contain names, phone numbers and lending records. Limit who can access it. The app only transfers data to the destination you select. Android Auto Backup and device transfer remain excluded. Uninstalling, clearing app data or losing a device can erase the library. Keep the backup outside the app's storage.

## File format

V1 uses a standard ZIP with the `.mlbak` extension. The archive contains these case-sensitive paths and omits explicit directory entries.

| Path | Contents |
| --- | --- |
| `manifest.json` | UTF-8 JSON manifest |
| `database/my_library.db` | Standalone SQLite database, schema 8 |
| `covers/<name>.jpg` | One entry per managed cover referenced by a book. Names contain 1–80 ASCII letters, digits or hyphens |

The manifest object has integer `formatVersion` (1), ISO 8601 UTC `createdAtUtc` ending in `Z`, `applicationId` (`com.kamilloo.mylibrary`), integer `schemaVersion` (8) and a `files` array. Each payload entry has a unique `path`, integer uncompressed `size` in bytes, and lowercase hexadecimal `sha256`. The inventory covers the database and all covers. The archive and total uncompressed payload are capped at 512 MiB each, the manifest at 4 MiB, and the entry count at 10,002. The Android reader checks the ZIP directory, allowed paths, duplicate names, inventory, byte counts, CRC-32 and SHA-256. The checksums detect corruption. They do not authenticate whoever created the file.

The snapshot includes books, genre assignments and registry, history, owner and borrower loans, QR records, SMS/manual borrowed entries, loan messages and decisions, local contacts, due-date overrides, reminder settings, SQLite sequences and local library preferences, including the preferred owner name. Remote cover URLs remain URLs. Platform permissions, pending OS notification records, device onboarding state, HTTP caches, temporary images, logs and signing credentials are outside the format.

## Consistency and recovery

The exporter waits for in-flight library writes and holds a SQLite transaction while it copies records and referenced covers. The snapshot is built with the production schema in a separate SQLite database, including stable IDs and the reminder sequence. It therefore reads committed rows through SQLite regardless of WAL or journal mode. Integrity and foreign keys are checked before the file is closed and archived. Staged SQLite files use DELETE journal mode so the archive contains a self-contained database, including on Android installations that default to retaining rollback journals. The app releases the database before interacting with the selected provider.

The importer streams the document to app-private storage and validates the ZIP before opening its database read-only. It checks the declared schema, database integrity, foreign keys and referenced covers, and copies the rows into a fresh database created with the trusted production schema. No SQL schema from the imported file runs against the active library. V1 supports format 1 with schema 8; future code must explicitly add validation and migration for any further supported schema pairing. Ordinary installed-app database migrations remain available independently of this format.

For replacement the app waits for in-flight writes and blocks new library writes. It publishes a private cover journal, writes incoming covers under fresh portable names, and changes all records in one transaction on the active database. The old records and cover files remain available for rollback until commit. SQLite decides which records survive interruption. On startup the app uses those records to keep the referenced covers, remove unreferenced restore candidates and clean stale workspaces. A crash before cleanup may temporarily leave duplicate cover bytes on disk. The app refreshes all library tabs after commit.

The reminder reconciler serializes restore with other notification work, uses the restored opt-in data and stable IDs, and removes obsolete reminder payloads without requesting permission. SQLite and Android's notification scheduler have separate state. A failure or process interruption during scheduling is repaired by reconciling with the database that survived, including on startup and resume. The first reconciliation in a new Android process registers the same eligible reminder IDs again because a force-stop can clear system alarms while the notification plugin retains its inventory.

The producer and consumer need free private storage for staging and can temporarily hold multiple copies of the library. A failed SAF write may leave an incomplete user-selected document depending on the provider. The app reports a failure and will reject an incomplete archive on import. Missing referenced local covers cause export to fail. Remote covers may require a network connection after restore.

Run the archive validation tests with `cd android && ./gradlew :app:testDebugUnitTest`.
JUnit runs those tests and the test-only JSON library provides the Android
`org.json` API on the host JVM. The app adds no runtime dependency.

See the [Android QA checklist](android_qa_checklist.md#task-32-manual-backup-and-recovery) for install, reinstall and device verification.
