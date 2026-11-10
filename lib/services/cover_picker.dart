import 'dart:io';

import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class CoverPicker {
  CoverPicker({
    ImagePicker? picker,
    ImageCropper? cropper,
    Future<Directory> Function()? temporaryDirectory,
  })  : _picker = picker ?? ImagePicker(),
        _cropper = cropper ?? ImageCropper(),
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory {
    final implementation = ImagePickerPlatform.instance;
    if (implementation is ImagePickerAndroid) {
      implementation.useAndroidPhotoPicker = true;
    }
  }
  final ImagePicker _picker;
  final ImageCropper _cropper;
  final Future<Directory> Function() _temporaryDirectory;
  // Only outputs returned by our own picker/cropper calls may be removed.
  final _temporaryOutputs = <String>{};

  Future<String?> pick(ImageSource source) async {
    final image = await _picker.pickImage(
      source: source,
      maxWidth: 2400,
      maxHeight: 2400,
      requestFullMetadata: false,
    );
    if (image == null) return null;
    _temporaryOutputs.add(image.path);
    String? result;
    try {
      result = await adjust(image.path);
      return result;
    } finally {
      if (result != image.path) await _discard(image.path);
    }
  }

  Future<String?> recover() async {
    final response = await _picker.retrieveLostData();
    if (response.exception != null) throw response.exception!;
    final files = response.files;
    if (files == null || files.isEmpty) return null;
    _temporaryOutputs.addAll(files.map((file) => file.path));
    String? result;
    try {
      result = await adjust(files.first.path);
      return result;
    } finally {
      for (final file in files) {
        if (file.path != result) await _discard(file.path);
      }
    }
  }

  Future<String?> adjust(String path) async {
    final result = await _cropper.cropImage(
      sourcePath: path,
      maxWidth: 1600,
      maxHeight: 2400,
      compressQuality: 88,
      uiSettings: [
        AndroidUiSettings(toolbarTitle: 'Dopasuj okładkę'),
        IOSUiSettings(
            title: 'Dopasuj okładkę',
            doneButtonTitle: 'Gotowe',
            cancelButtonTitle: 'Anuluj'),
      ],
    );
    // The input can belong to a book or the user. Never assume ownership of it.
    if (result != null && result.path != path) {
      _temporaryOutputs.add(result.path);
    }
    return result?.path;
  }

  /// Retain the displayed draft until save copies it into persistent storage.
  Future<void> releaseExcept([String? keep]) async {
    for (final path in _temporaryOutputs.toList()) {
      if (path != keep) await _discard(path);
    }
  }

  Future<void> _discard(String path) async {
    if (!_temporaryOutputs.contains(path)) return;
    try {
      final cache = await (await _temporaryDirectory()).resolveSymbolicLinks();
      final file = File(path);
      if (!await file.exists()) {
        _temporaryOutputs.remove(path);
        return;
      }
      final actual = await file.resolveSymbolicLinks();
      // Containment alone is insufficient: also require recorded plugin origin.
      // Canonical paths reject symlinks that escape the app's private cache.
      if (p.isWithin(cache, actual)) await file.delete();
      _temporaryOutputs.remove(path);
    } catch (_) {
      // Retry on the next release; cleanup must not prevent selection or saving.
    }
  }
}
