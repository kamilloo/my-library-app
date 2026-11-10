import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// SQLite stores only URLs or portable paths relative to application support.
class CoverStorage {
  CoverStorage({Future<Directory> Function()? directory})
      : _directory = directory ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _directory;

  static bool isNetwork(String reference) =>
      Uri.tryParse(reference)?.scheme == 'https' ||
      Uri.tryParse(reference)?.scheme == 'http';

  static bool isManaged(String reference) =>
      RegExp(r'^covers/[a-zA-Z0-9-]+\.jpg$').hasMatch(reference);

  Future<File> resolve(String reference) async => File(isManaged(reference)
      ? p.join((await _directory()).path, reference)
      : reference);

  Future<String?> persist(String? reference) async {
    if (reference == null || reference.isEmpty) return null;
    if (isNetwork(reference) || isManaged(reference)) return reference;
    final directory = Directory(p.join((await _directory()).path, 'covers'));
    await directory.create(recursive: true);
    final name = '${const Uuid().v4()}.jpg';
    final destination = File(p.join(directory.path, name));
    try {
      await File(reference).copy(destination.path);
    } catch (_) {
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
    return 'covers/$name';
  }

  Future<void> delete(String? reference) async {
    if (reference == null || !isManaged(reference)) return;
    try {
      final file = await resolve(reference);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // A failed cleanup must never turn a committed book save into a failure.
    }
  }
}
