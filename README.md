# My Library

Local-first Flutter MVP for cataloging books and tracking lending.

## Included

- SQLite data model with UUIDs and timestamps
- Library search, status filters, and sorting
- Add-book form
- Book details, lend, return, and history flows
- Camera barcode/QR scanning with ISBN validation
- Open Library metadata lookup and Add Book form prefilling
- Seed books on first launch

## Run

Flutter was not available in the generation environment, so create platform
scaffolding once before the first run:

```bash
flutter create --platforms=android,ios .
flutter pub get
flutter run
```

The source targets Flutter 3.22+ and Dart 3.4+.

## Camera permissions

After generating the Android and iOS folders, apply the changes documented in
[`docs/camera_permissions.md`](docs/camera_permissions.md). The scanner cannot
open the camera until those platform declarations are present.
