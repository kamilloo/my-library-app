import 'dart:typed_data';

const maxBackupBytes = 64 * 1024 * 1024;

Future<bool> offlineResourcesReady() async => false;

Future<Uint8List?> selectBackup() => throw UnsupportedError('Browser only');

void downloadBackup(String name, Uint8List bytes) =>
    throw UnsupportedError('Browser only');

Future<Uint8List> photoAsJpeg(String url) =>
    throw UnsupportedError('Browser only');

void releasePhoto(String url) {}
