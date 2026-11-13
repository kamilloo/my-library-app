# My Library

Current Android V1 scope, feature statuses, schema and release gates:
[canonical specification](docs/MyLibrary_Version_1_Updated_Specification.txt).
See the [historical comparison](docs/specification_gap_analysis.md) for reconciled requirements.

## Offline SMS loan messages

Android supports user-reviewed SMS invitations, extension requests and decisions,
with explicit local approval import. No automatic SMS sending/reading or cloud
synchronization is used. See [offline loan messaging](docs/offline_loan_messaging.md)
for v1 QR compatibility, local contact storage, authenticity limits and device QA.



Local-first Flutter MVP for cataloging books and tracking lending.

## Included

- SQLite data model with UUIDs and timestamps
- Library search, status filters, and sorting
- Add-book form
- Book details, lend, return, and history flows
- Camera barcode/QR scanning with ISBN validation
- Open Library metadata lookup and Add Book form prefilling

Database safety, supported migration paths, regression coverage and Android
upgrade checks: [SQLite regression audit](docs/sqlite_regression_audit.md).

## Run

Use Flutter **3.47.5** / Dart **3.13.4** (the CI versions), JDK 17,
and Android SDK platform 37.0. Android is supported from API 24 (Android 7.0);
the current target is API 36. The Android project is already checked in.

```bash
flutter pub get
flutter run
```

See [Android release preparation](docs/android_release.md) for signing, versioning,
artifact verification, backup policy and release blockers, and the
[Android QA checklist](docs/android_qa_checklist.md) for executed checks and pending
physical-device tests. Release builds require privately supplied signing
credentials; no production key is included or generated.

## Search Open Library by title or author

In Add Book, choose **Szukaj książki po tytule lub autorze**. Enter a title,
author, or both and press **Szukaj**. Searches are explicit GET requests through
the existing Open Library service; opening the screen or editing text does not
send requests. Results show available cover/title/author/year metadata. **Pokaż
więcej** requests another page, capped at five pages of 20 results (100 total).
No individual work/edition details are fetched.

Selecting a result fills empty form fields. If available metadata differs from
populated fields, choose whether to replace it, fill only empty fields, or cancel.
A local cover is retained unless replacement is explicitly confirmed. Selection
does not save anything; edit the form and press **Zapisz książkę** to insert a book.

Search normally returns works spanning multiple editions. These results never
supply an assumed physical-book ISBN, even when only one ISBN is listed. ISBN is
filled only for an explicit edition record with one matching edition identifier
and exactly one valid normalized ISBN. Otherwise an empty ISBN stays empty and
an existing user-entered ISBN stays intact. Enter/scan the actual ISBN separately.

Polish error/retry states cover offline requests, timeouts, HTTP errors, malformed
responses, and no results. Older responses cannot replace newer query results;
identical pending query/page requests share a future. Requests are not auto-retried.
Manual entry, local covers, and offline library access remain available. Existing
network cover URLs need connectivity to display their images; missing images use
placeholders. No schema, account, remote library writes, descriptions, or category
management are added.

API: [Open Library Search documentation](https://openlibrary.org/dev/docs/api/search).

## Camera permissions

Android camera permission is declared for scanning and cover photography and
requested when using those features. Gallery selection uses the system picker,
without broad storage permission. Notification authorization is requested only
after reminder opt-in. See the [Android permission audit](docs/android_release.md#permissions-and-components).

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

## Extend an existing loan (Prolongata)

For a borrowed book, **Przedłuż wypożyczenie** offers **+7 dni**, **+14 dni**,
**+30 dni**, and **Wybierz datę**, with a date preview before confirmation.
Presets add calendar days to the saved return date, including across month ends,
leap years and DST transitions. Without a saved date, choose one explicitly.

The resulting date must be later than the existing term and after today.
Overdue loans may be extended, but a preset that still leaves the loan overdue
cannot be confirmed. Borrower, original borrowing date, status, and metadata stay
unchanged. One `loan_extended` history entry and the new return date commit
together through the same date-update transaction used above. Repeated submissions
of the same date cannot append another event. Enabled reminders keep their opt-in
and stable ID, and reconcile after commit; OS failures are retried on app resume.

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
`pubspec.lock`, which requires Flutter 3.47+ and Dart 3.13+. It caches the
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
