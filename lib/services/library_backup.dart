import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../data/library_database.dart';
import '../models/book.dart';
import 'cover_storage.dart';
import 'return_reminders.dart';

class RestoreFailure implements Exception {
  const RestoreFailure({required this.previousLibraryVerified});

  final bool previousLibraryVerified;
}

class LibraryBackup {
  LibraryBackup({
    LibraryDatabase? database,
    Future<Directory> Function()? support,
    this.reminders,
  })  : database = database ?? LibraryDatabase.instance,
        _support = support ?? getApplicationSupportDirectory;

  final LibraryDatabase database;
  final ReturnReminders? reminders;
  static final revision = ValueNotifier(0);
  final Future<Directory> Function() _support;
  static const _channel = MethodChannel('my_library/backup');
  static const _databasePath = 'database/my_library.db';
  static const _tables = [
    'books',
    'genres',
    'history',
    'return_reminders',
    'owner_loan_instances',
    'loan_transfers',
    'borrowed_loans',
    'loan_messages',
    'loan_contacts',
    'local_borrowed_entries',
    'borrowed_due_overrides',
    'local_preferences',
    'sqlite_sequence',
  ];

  Future<Directory> _root() async =>
      Directory(p.join((await _support()).path, 'manual_backup'));

  Future<Directory> workspace() async {
    final root = await _root();
    await root.create(recursive: true);
    return root.createTemp('job-');
  }

  Future<bool> export(Directory work) async {
    final directory = Directory(p.join(work.path, 'export'));
    final dbFile = File(p.join(directory.path, _databasePath));
    await dbFile.parent.create(recursive: true);
    final snapshot = await database.openBackupDatabase(dbFile.path);
    try {
      final active = await database.database;
      final support = await _support();
      await database.exclusive(() => active.transaction((source) async {
            await snapshot.transaction((target) => _copyRows(source, target));
            for (final reference in await _coverReferences(source)) {
              final file = File(p.join(directory.path, reference));
              await file.parent.create(recursive: true);
              await File(p.join(support.path, reference)).copy(file.path);
            }
          }));
      await _verify(snapshot);
    } finally {
      await snapshot.close();
    }
    final date = DateTime.now().toIso8601String().split('T').first;
    return await _channel.invokeMethod<bool>('export', {
          'path': work.path,
          'name': 'MojaBiblioteka-backup-$date.mlbak',
          'schema': LibraryDatabase.schemaVersion,
        }) ??
        false;
  }

  Future<bool> prepareRestore(Directory work) async {
    final selected = await _channel.invokeMethod<bool>('import', {
      'path': work.path,
      'schema': LibraryDatabase.schemaVersion,
    });
    if (selected != true) return false;
    await validateRestore(work);
    return true;
  }

  Future<void> validateRestore(Directory work) async {
    final input = Directory(p.join(work.path, 'import'));
    final trusted =
        await database.openBackupDatabase(p.join(work.path, 'verified.db'));
    Database? opened;
    try {
      final source = opened = await database.openBackupDatabase(
        p.join(input.path, _databasePath),
        readOnly: true,
      );
      if (await source.getVersion() != LibraryDatabase.schemaVersion) {
        throw const FormatException('Invalid database version');
      }
      final expected = await _layout(trusted);
      if (jsonEncode(await _layout(source)) != jsonEncode(expected)) {
        throw const FormatException('Invalid database schema');
      }
      await _verify(source);
      final references = await _coverReferences(source);
      final covers = Directory(p.join(input.path, 'covers'));
      final files = await covers.exists()
          ? await covers
              .list()
              .map((entry) => 'covers/${p.basename(entry.path)}')
              .toSet()
          : <String>{};
      if (references.length != files.length || !references.containsAll(files)) {
        throw const FormatException('Invalid cover inventory');
      }
      await trusted.transaction((target) => _copyRows(source, target));
      await _verify(trusted);
    } finally {
      try {
        await opened?.close();
      } finally {
        await trusted.close();
      }
    }
  }

  Future<void> restore(Directory work) async {
    await database.exclusive(() async {
      await recoverCovers();
      final reminderService = reminders;
      if (reminderService == null) {
        await _restore(work, (_) async {});
      } else {
        await reminderService
            .replaceLibrary((reconcile) => _restore(work, reconcile));
      }
    });
    revision.value++;
  }

  Future<bool> _checkActive() async {
    try {
      final active = await database.database;
      final support = await _support();
      await _verify(active);
      for (final path in await _coverReferences(active, strict: false)) {
        if (!await File(p.join(support.path, path)).exists()) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _restore(
      Directory work, Future<void> Function(DatabaseExecutor) reconcile) async {
    final source = await database.openBackupDatabase(
      p.join(work.path, 'verified.db'),
      readOnly: true,
    );
    var sourceClosed = false;
    var committing = false;
    try {
      final active = await database.database;
      final support = await _support();
      final input = Directory(p.join(work.path, 'import'));
      await active.transaction((target) async {
        final old = await _coverReferences(target, strict: false);
        final names = {
          for (final path in await _coverReferences(source))
            path: 'covers/${const Uuid().v4()}.jpg',
        };
        final root = await _root();
        final journal = File(p.join(root.path, 'covers.json'));
        // Publish the journal before creating any new cover. SQLite determines
        // which set is live if the process exits before cleanup.
        final pending = File('${journal.path}.next');
        await pending.writeAsString(jsonEncode([...old, ...names.values]),
            flush: true);
        await pending.rename(journal.path);
        await _syncDirectories(['manual_backup', '']);
        for (final entry in names.entries) {
          final destination = File(p.join(support.path, entry.value));
          await destination.parent.create(recursive: true);
          await destination.create(exclusive: true);
          final output = await destination.open(mode: FileMode.writeOnly);
          try {
            await for (final chunk
                in File(p.join(input.path, entry.key)).openRead()) {
              await output.writeFrom(chunk);
            }
            await output.flush();
          } finally {
            await output.close();
          }
        }
        if (names.isNotEmpty) await _syncDirectories(['covers', '']);
        await _copyRows(source, target, remap: names);
        await source.close();
        sourceClosed = true;
        await _verify(target);
        await reconcile(target);
        committing = true;
      });
    } catch (_) {
      // If the commit itself failed, integrity alone cannot identify the
      // surviving dataset. Only report verified rollback before that point.
      throw RestoreFailure(
          previousLibraryVerified: !committing && await _checkActive());
    } finally {
      try {
        if (!sourceClosed) await source.close();
      } catch (_) {
        // Private staging is safe to clean on startup if closing fails.
      } finally {
        try {
          await recoverCovers();
        } catch (_) {
          // The published journal allows cleanup to be retried at startup.
        }
      }
    }
  }

  static Future<void> _syncDirectories(List<String> names) async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('syncDirectories', {'names': names});
    }
  }

  Future<void> recoverCovers({bool startup = false}) async {
    final root = await _root();
    if (!await root.exists()) return;
    final journal = File(p.join(root.path, 'covers.json'));
    if (await journal.exists()) {
      final candidates =
          (jsonDecode(await journal.readAsString()) as List).cast<String>();
      final active = await database.database;
      final support = await _support();
      await active.transaction((txn) async {
        final live = await _coverReferences(txn, strict: false);
        for (final path in candidates) {
          if (!CoverStorage.isManaged(path) || live.contains(path)) continue;
          final file = File(p.join(support.path, path));
          if (await file.exists()) await file.delete();
        }
        await journal.delete();
      });
    }
    if (startup) {
      await for (final entity in root.list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (name.startsWith('job-') || name == 'covers.json.next') {
          await entity.delete(recursive: true);
        }
      }
    }
  }

  static Future<Set<String>> _coverReferences(DatabaseExecutor db,
      {bool strict = true}) async {
    final rows = await db.rawQuery(
        "SELECT DISTINCT cover_url FROM books WHERE cover_url IS NOT NULL AND cover_url <> ''");
    final paths = <String>{};
    for (final row in rows) {
      final path = row['cover_url'] as String;
      if (CoverStorage.isManaged(path)) {
        paths.add(path);
      } else if (strict && !CoverStorage.isNetwork(path)) {
        throw const FormatException('Invalid local cover path');
      }
    }
    return paths;
  }

  static Future<void> _verify(DatabaseExecutor db) async {
    final integrity = await db.rawQuery('PRAGMA integrity_check');
    if (integrity.length != 1 ||
        integrity.single.values.single != 'ok' ||
        (await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
      throw const FormatException('Invalid database integrity');
    }
  }

  static Future<Map<String, Object>> _layout(DatabaseExecutor db) async {
    final objects = await db.rawQuery(
      "SELECT type, name, sql FROM sqlite_master WHERE name NOT GLOB 'sqlite_autoindex_*' ORDER BY type, name",
    );
    return {
      'objects': objects,
      for (final table in _tables)
        table: {
          'columns': (await db.rawQuery('PRAGMA table_info($table)'))
              .map((row) => Map.of(row)..remove('cid'))
              .toList()
            ..sort(
                (a, b) => (a['name'] as String).compareTo(b['name'] as String)),
          'foreignKeys': await db.rawQuery('PRAGMA foreign_key_list($table)'),
          'indexes': await db.rawQuery('PRAGMA index_list($table)'),
        },
    };
  }

  static Future<void> _copyRows(
      DatabaseExecutor source, DatabaseExecutor target,
      {Map<String, String> remap = const {}}) async {
    for (final table in _tables.reversed) {
      await target.delete(table);
    }
    for (final table in _tables) {
      var last = -9223372036854775808;
      var initial = true;
      while (true) {
        final rows = await source.rawQuery(
          'SELECT rowid AS backup_rowid, * FROM $table '
          '${initial ? '' : 'WHERE rowid > ?'} ORDER BY rowid LIMIT 128',
          initial ? null : [last],
        );
        if (rows.isEmpty) break;
        final batch = target.batch();
        for (final row in rows) {
          final values = Map<String, Object?>.of(row)..remove('backup_rowid');
          if (table == 'history') HistoryEntry.fromMap(values);
          if (table == 'books') {
            Book.fromMap(values);
            final replacement = remap[values['cover_url']];
            if (replacement != null) values['cover_url'] = replacement;
          }
          batch.insert(table, values);
        }
        await batch.commit(noResult: true);
        last = rows.last['backup_rowid'] as int;
        initial = false;
      }
    }
  }
}
