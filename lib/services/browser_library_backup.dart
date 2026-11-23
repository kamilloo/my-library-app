part of 'library_backup.dart';

class BrowserLibraryBackup {
  BrowserLibraryBackup([LibraryDatabase? database])
      : _database = database ?? LibraryDatabase.instance;

  final LibraryDatabase _database;
  static const _manifest = 'manifest.json';
  static const _applicationId = 'com.kamilloo.mylibrary';
  static const _manifestLimit = 4 * 1024 * 1024;
  static const _entryLimit = 10002;

  String get exportName {
    final date = DateTime.now().toUtc().toIso8601String().split('T').first;
    return 'MojaBiblioteka-backup-$date.mlbak';
  }

  Future<Uint8List> export() async {
    final path = _temporaryPath();
    final factory = databaseFactoryFfiWeb;
    final covers = <String, Uint8List>{};
    try {
      final snapshot = await _database.openBackupDatabase(path);
      try {
        final active = await _database.database;
        await _database.exclusive(() => active.transaction((source) async {
              await snapshot.transaction(
                  (target) => LibraryBackup._copyRows(source, target));
              var size = 0;
              for (final reference
                  in await LibraryBackup._coverReferences(source)) {
                final rows = await source.query('browser_covers',
                    columns: ['bytes'],
                    where: 'path = ?',
                    whereArgs: [reference]);
                final bytes = rows.single['bytes']! as Uint8List;
                size += bytes.length;
                if (size > maxBackupBytes || covers.length >= _entryLimit - 2) {
                  throw const FormatException('Backup exceeds browser limit');
                }
                covers[reference] = bytes;
              }
            }));
        await LibraryBackup._verify(snapshot);
      } finally {
        await snapshot.close();
      }
      final bytes = await factory.readDatabaseBytes(path);
      if (bytes.isEmpty) {
        throw StateError('Missing SQLite snapshot');
      }
      return _encode({LibraryBackup._databasePath: bytes, ...covers});
    } finally {
      await factory.deleteDatabase(path);
    }
  }

  Future<({String verifiedPath, Map<String, Uint8List> covers})?>
      prepareRestore() async {
    final selected = await selectBackup();
    if (selected == null) return null;
    final files = _decode(selected);
    final databaseBytes = files.remove(LibraryBackup._databasePath)!;
    final path = _temporaryPath();
    final verifiedPath = _temporaryPath();
    final factory = databaseFactoryFfiWeb;
    try {
      await factory.writeDatabaseBytes(path, databaseBytes);
      final source = await _database.openBackupDatabase(path, readOnly: true);
      try {
        await source.execute('PRAGMA trusted_schema = OFF');
        final trusted = await _database.openBackupDatabase(verifiedPath);
        try {
          if (await source.getVersion() != LibraryDatabase.schemaVersion ||
              jsonEncode(await LibraryBackup._layout(source)) !=
                  jsonEncode(await LibraryBackup._layout(trusted))) {
            throw const FormatException('Invalid database schema');
          }
          await LibraryBackup._verify(source);
          final references = await LibraryBackup._coverReferences(source);
          if (references.length != files.length ||
              !references.containsAll(files.keys)) {
            throw const FormatException('Invalid cover inventory');
          }
          await trusted
              .transaction((target) => LibraryBackup._copyRows(source, target));
          await LibraryBackup._verify(trusted);
        } finally {
          await trusted.close();
        }
      } finally {
        await source.close();
      }
      return (verifiedPath: verifiedPath, covers: files);
    } catch (_) {
      await discard(verifiedPath);
      rethrow;
    } finally {
      await discard(path);
    }
  }

  Future<void> restore(
      String verifiedPath, Map<String, Uint8List> covers) async {
    await _database.exclusive(() async {
      final source =
          await _database.openBackupDatabase(verifiedPath, readOnly: true);
      try {
        final active = await _database.database;
        await active.transaction((target) async {
          await target.delete('browser_covers');
          final batch = target.batch();
          for (final cover in covers.entries) {
            batch.insert('browser_covers', {
              'path': cover.key,
              'bytes': cover.value,
            });
          }
          await batch.commit(noResult: true);
          await LibraryBackup._copyRows(source, target);
          await LibraryBackup._verify(target);
        });
      } finally {
        await source.close();
      }
    });
    LibraryBackup.revision.value++;
  }

  Future<void> discard(String path) =>
      databaseFactoryFfiWeb.deleteDatabase(path);

  static String _temporaryPath() => 'backup-${const Uuid().v4()}.db';

  static Uint8List _encode(Map<String, Uint8List> files) {
    if (files.values.fold<int>(0, (sum, bytes) => sum + bytes.length) >
        maxBackupBytes) {
      throw const FormatException('Backup exceeds browser limit');
    }
    final archive = Archive();
    final inventory = [
      for (final entry in files.entries)
        {
          'path': entry.key,
          'size': entry.value.length,
          'sha256': sha256.convert(entry.value).toString(),
        },
    ];
    final manifest = utf8.encode(jsonEncode({
      'formatVersion': 1,
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'applicationId': _applicationId,
      'schemaVersion': LibraryDatabase.schemaVersion,
      'files': inventory,
    }));
    archive.addFile(ArchiveFile.bytes(_manifest, manifest));
    for (final entry in files.entries) {
      archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
    }
    final result = ZipEncoder().encodeBytes(archive);
    if (result.length > maxBackupBytes) {
      throw const FormatException('Backup exceeds browser limit');
    }
    return result;
  }

  static Map<String, Uint8List> _decode(Uint8List bytes) {
    final directory = ZipDirectory();
    final names = <String>{};
    var total = 0;
    for (final header
        in directory.headers(InputMemoryStream(bytes), files: false)) {
      final name = header.filename;
      final size = header.uncompressedSize;
      total += size;
      if (!names.add(name) ||
          names.length > _entryLimit ||
          header.generalPurposeBitFlag & 1 != 0 ||
          size <= 0 ||
          total > maxBackupBytes ||
          (name == _manifest && size > _manifestLimit) ||
          (name != _manifest &&
              name != LibraryBackup._databasePath &&
              !RegExp(r'^covers/[a-zA-Z0-9-]{1,80}\.jpg$').hasMatch(name))) {
        throw const FormatException('Invalid backup entries');
      }
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    if (archive.length != names.length ||
        !names.containsAll([_manifest, LibraryBackup._databasePath])) {
      throw const FormatException('Invalid backup ZIP');
    }
    final payload = <String, Uint8List>{};
    for (final file in archive) {
      if (!file.isFile || !names.contains(file.name)) {
        throw const FormatException('Invalid backup entry');
      }
      payload[file.name] = file.content;
    }
    final manifest = jsonDecode(utf8.decode(payload.remove(_manifest)!))
        as Map<String, dynamic>;
    if (manifest['schemaVersion'] case final int schema
        when schema > LibraryDatabase.schemaVersion) {
      throw PlatformException(code: 'future_version');
    }
    final created = manifest['createdAtUtc'] as String;
    if (manifest['applicationId'] != _applicationId ||
        manifest['formatVersion'] != 1 ||
        manifest['schemaVersion'] != LibraryDatabase.schemaVersion ||
        !created.endsWith('Z') ||
        DateTime.tryParse(created) == null) {
      throw const FormatException('Invalid backup manifest');
    }
    final listed = <String>{};
    for (final item in manifest['files'] as List<dynamic>) {
      final name = item['path'] as String;
      final content = payload[name];
      if (!listed.add(name) ||
          content == null ||
          item['size'] != content.length ||
          item['sha256'] != sha256.convert(content).toString()) {
        throw const FormatException('Invalid backup checksum');
      }
    }
    if (listed.length != payload.length) {
      throw const FormatException('Incomplete backup inventory');
    }
    return payload;
  }
}
