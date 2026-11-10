import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:my_library/services/cover_picker.dart';

class DevicePicker extends ImagePicker {
  String? output;
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async =>
      output == null ? null : XFile(output!);
}

class Cropper extends ImageCropper {
  String? output;
  bool fail = false;
  @override
  Future<CroppedFile?> cropImage({
    required String sourcePath,
    int? maxWidth,
    int? maxHeight,
    CropAspectRatio? aspectRatio,
    ImageCompressFormat compressFormat = ImageCompressFormat.jpg,
    int compressQuality = 90,
    List<PlatformUiSettings>? uiSettings,
  }) async {
    if (fail) throw StateError('Crop failed');
    return output == null ? null : CroppedFile(output!);
  }
}

void main() {
  late Directory root;
  late Directory cache;
  late DevicePicker device;
  late Cropper cropper;
  late CoverPicker picker;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cover-picker-test');
    cache = await Directory('${root.path}/cache').create();
    device = DevicePicker();
    cropper = Cropper();
    picker = CoverPicker(
        picker: device,
        cropper: cropper,
        temporaryDirectory: () async => cache);
  });
  tearDown(() => root.delete(recursive: true));

  Future<String> file(String path) async {
    final result = File('${root.path}/$path');
    await result.parent.create(recursive: true);
    await result.writeAsBytes([1, 2, 3]);
    return result.path;
  }

  test(
      'camera crop keeps preview and removes raw output; leaving discards draft',
      () async {
    device.output = await file('cache/camera.jpg');
    cropper.output = await file('cache/crop.jpg');
    final selected = await picker.pick(ImageSource.camera);
    expect(await File(device.output!).exists(), isFalse);
    await picker.releaseExcept(selected);
    expect(await File(selected!).exists(), isTrue);
    await picker.releaseExcept();
    expect(await File(selected).exists(), isFalse);
  });

  test('crop cancellation and failure remove owned raw output', () async {
    for (final fail in [false, true]) {
      device.output = await file('cache/camera.jpg');
      cropper.fail = fail;
      if (fail) {
        await expectLater(picker.pick(ImageSource.camera), throwsStateError);
      } else {
        expect(await picker.pick(ImageSource.camera), isNull);
      }
      expect(await File(device.output!).exists(), isFalse);
    }
  });

  test('replacement removes previous draft and preserves new preview',
      () async {
    device.output = await file('cache/picked.jpg');
    cropper.output = await file('cache/first.jpg');
    final first = await picker.pick(ImageSource.gallery);
    device.output = await file('cache/next.jpg');
    cropper.output = await file('cache/second.jpg');
    final second = await picker.pick(ImageSource.gallery);
    await picker.releaseExcept(second);
    expect(await File(first!).exists(), isFalse);
    expect(await File(second!).exists(), isTrue);
    await picker.releaseExcept();
    expect(await File(second).exists(), isFalse);
  });

  test('canceling another pick retains the existing draft', () async {
    device.output = await file('cache/picked.jpg');
    cropper.output = await file('cache/first.jpg');
    final first = await picker.pick(ImageSource.gallery);
    device.output = null;
    expect(await picker.pick(ImageSource.gallery), isNull);
    await picker.releaseExcept(first);
    expect(await File(first!).exists(), isTrue);
  });

  test('external gallery and persistent managed input are never deleted',
      () async {
    device.output = await file('gallery/user.jpg');
    final managed = await file('support/covers/book.jpg');
    cropper.output = await file('cache/first.jpg');
    await picker.pick(ImageSource.gallery);
    cropper.output = await file('cache/second.jpg');
    await picker.adjust(managed);
    await picker.releaseExcept();
    expect(await File(device.output!).exists(), isTrue);
    expect(await File(managed).exists(), isTrue);
  });

  test(
      'untracked cache files and plugin outputs outside private cache are preserved',
      () async {
    final unrelated = await file('cache/unrelated.jpg');
    final externalOutput = await file('gallery/output.jpg');
    cropper.output = externalOutput;
    await picker.adjust(unrelated);
    await picker.releaseExcept();
    expect(await File(unrelated).exists(), isTrue);
    expect(await File(externalOutput).exists(), isTrue);
  });

  test('symlink output cannot delete an external target', () async {
    final external = await file('gallery/user.jpg');
    final link = await Link('${cache.path}/link.jpg').create(external);
    device.output = link.path;
    await picker.pick(ImageSource.gallery);
    await picker.releaseExcept();
    expect(await File(external).exists(), isTrue);
    expect(await link.exists(), isTrue);
  });

  test('identical crop input and output is retained until release', () async {
    device.output = await file('cache/picked.jpg');
    cropper.output = device.output;
    final result = await picker.pick(ImageSource.gallery);
    expect(await File(result!).exists(), isTrue);
    await picker.releaseExcept();
    expect(await File(result).exists(), isFalse);
  });
}
