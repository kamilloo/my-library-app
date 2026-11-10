import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

class CoverPicker {
  CoverPicker() {
    final implementation = ImagePickerPlatform.instance;
    if (implementation is ImagePickerAndroid) {
      implementation.useAndroidPhotoPicker = true;
    }
  }
  final _picker = ImagePicker();

  Future<String?> pick(ImageSource source) async {
    final image = await _picker.pickImage(
      source: source,
      maxWidth: 2400,
      maxHeight: 2400,
      requestFullMetadata: false,
    );
    return image == null ? null : adjust(image.path);
  }

  Future<String?> recover() async {
    final response = await _picker.retrieveLostData();
    if (response.exception != null) throw response.exception!;
    final files = response.files;
    return files == null || files.isEmpty ? null : adjust(files.first.path);
  }

  Future<String?> adjust(String path) async {
    final result = await ImageCropper().cropImage(
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
    return result?.path;
  }
}
