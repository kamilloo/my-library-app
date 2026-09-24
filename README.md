# My Library

Local-first Flutter MVP for cataloging books and tracking lending.

## Included

- SQLite data model with UUIDs and timestamps
- Library search, status filters, and sorting
- Add-book form
- Book details, lend, return, and history flows
- Open Library lookup service and scanner dependency prepared for integration
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

## Next integration step

Connect `mobile_scanner` to the Add Book screen and pass detected ISBN values to
`OpenLibraryService.lookupByIsbn`. Add Android camera permission and the iOS
camera usage description when platform folders are generated.
