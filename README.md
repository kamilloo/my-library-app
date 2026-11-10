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

## Change return date

For a borrowed book, Book Details shows the saved return date or
**Nie ustawiono terminu zwrotu**. Use **Zmień termin zwrotu** to select today or
a future date, or **Usuń termin zwrotu** to clear it explicitly. The picker
initially selects the saved date, including an overdue date (saving that unchanged
date is a no-op).

Actual calendar-date changes append a Polish `return_date_changed` event in the
same SQLite transaction as the date update. Borrower, original lending date,
status, book metadata, and previous history remain intact. Enabled reminders are
rescheduled or canceled after commit without clearing the user's opt-in; an OS
notification failure does not undo the saved date or history.

## Return-date reminders

Borrowed books support optional local reminders at 09:00 on the return date.
Enable **Przypomnij o zwrocie** in Book Details. No account is needed.
See [setup, limits, and physical-device verification](docs/return_reminders.md).

## CI

[Flutter CI](https://github.com/kamilloo/my-library-app/actions/workflows/flutter-ci.yml)
runs for pull requests targeting `main`, pushes to `main`, and manual runs
from the Actions tab using **Run workflow** (available after the workflow is on
the default branch). New runs cancel older runs for the same branch or PR.

CI pins stable Flutter **3.47.5** (Dart **3.13.4**) to support the committed
`pubspec.lock`, which requires Flutter 3.44+ and Dart 3.12+. It caches the
Flutter SDK, pub dependencies, and Android Gradle dependencies, and fails if
dependency resolution changes the lockfile.

Run the same quality checks locally, in order, with that Flutter version:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

All unit and widget tests run, including the duplicate ISBN tests. A failed
check stops the job. After quality checks pass, a separate job uses Java 17
and the Android SDK to run `flutter build apk --debug`; this command can also
be run locally with those prerequisites. No production signing secrets are
needed.

To download the APK, open a successful **Flutter CI** run in the repository's
**Actions** tab and select **my-library-debug-apk** in **Artifacts**. Unzip the
download to obtain `app-debug.apk`. Artifacts are retained for **7 days**.
