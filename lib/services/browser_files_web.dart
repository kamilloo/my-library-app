import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

const maxBackupBytes = 64 * 1024 * 1024;

@JS('mojaBibliotekaOfflineReady')
external JSPromise<JSBoolean> _offlineResourcesReady();

Future<bool> offlineResourcesReady() async {
  try {
    return (await _offlineResourcesReady().toDart).toDart;
  } catch (_) {
    return false;
  }
}

Future<Uint8List?> selectBackup() async {
  // Safari Files can treat an Android .mlbak as a generic document.
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..hidden = true.toJS;
  final result = Completer<web.File?>();
  input.addEventListener(
      'change',
      ((web.Event _) {
        if (!result.isCompleted) result.complete(input.files?.item(0));
      }).toJS);
  input.addEventListener(
      'cancel',
      ((web.Event _) {
        if (!result.isCompleted) result.complete(null);
      }).toJS);
  web.document.body!.append(input);
  try {
    input.click();
    final file = await result.future;
    if (file == null) return null;
    if (file.size > maxBackupBytes) {
      throw const FormatException('Backup exceeds Safari size limit');
    }
    return (await file.arrayBuffer().toDart).toDart.asUint8List();
  } finally {
    input.remove();
  }
}

void downloadBackup(String name, Uint8List bytes) {
  final url = web.URL.createObjectURL(web.Blob(
      <JSAny>[bytes.toJS].toJS, web.BlobPropertyBag(type: 'application/zip')));
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = name
    ..hidden = true.toJS;
  web.document.body!.append(link);
  link.click();
  link.remove();
  // Safari may consume the URL after the event callback has returned.
  Future<void>.delayed(const Duration(minutes: 1), () {
    web.URL.revokeObjectURL(url);
  });
}

Future<Uint8List> photoAsJpeg(String url) async {
  final image = web.HTMLImageElement()..src = url;
  await image.decode().toDart;
  final width = image.naturalWidth;
  final height = image.naturalHeight;
  if (width == 0 || height == 0) throw const FormatException('Invalid photo');
  final scale = (1600 / width).clamp(0.0, 1.0);
  final ratio = (2400 / height).clamp(0.0, scale);
  final canvas = web.HTMLCanvasElement()
    ..width = (width * ratio).round().clamp(1, 1600)
    ..height = (height * ratio).round().clamp(1, 2400);
  final context = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
  context.fillStyle = '#ffffff'.toJS;
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.drawImage(image, 0, 0, canvas.width, canvas.height);
  return UriData.parse(canvas.toDataURL('image/jpeg', 0.88.toJS))
      .contentAsBytes();
}

void releasePhoto(String url) => web.URL.revokeObjectURL(url);
