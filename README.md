# My Library

Current Android V1 scope, feature statuses, schema and release gates:
[canonical specification](docs/MyLibrary_Version_1_Updated_Specification.txt).
See the [historical comparison](docs/specification_gap_analysis.md) for reconciled requirements.

## Safari na iPhonie

Moja Biblioteka w przeglądarce jest przeznaczona dla Safari na iPhonie.
Na Androidzie zalecamy aplikację natywną.
[Budowanie, publikacja HTTPS i weryfikacja zadania 33](docs/task33_iphone_safari.md).

## Dobrowolne wsparcie

W aplikacji otwórz **Pomoc → Wesprzyj Moją Bibliotekę**. Safari na iPhonie
oferuje dobrowolną wpłatę przez BuyCoffee.to bez nagród. Android ma osobną integrację Google Play
dla jednorazowego zakupu kosmetycznej odznaki **Przyjaciel Biblioteki**.
Po potwierdzeniu własności odznaka pojawia się po lewej stronie tytułu **Pomoc**.
Zakup jest dostępny w Androidzie wyłącznie w kompilacji debug z flagą
`PLAY_SUPPORTER_BILLING_TEST=true`.
Wszystkie funkcje biblioteki pozostają bezpłatne.

Odznakę przywraca się z tego samego konta Google Play przyciskiem **Przywróć zakup**.
Kopia biblioteki nie zawiera odznaki. Po zwrocie z odebraniem zakupu odznaka
znika po udanym odświeżeniu własności w Play. Szczegóły i ograniczenia lokalnej
weryfikacji opisują [zasady wsparcia](docs/voluntary_support.md) oraz
[lista konfiguracji i testów w Google Play](docs/google_play_supporter_badge.md).

## Main screens and offline search

**Moje książki**, **Historia** and **Pożyczone** each have a search bar and
**Pomoc**. Search by title or author, or by owner name in **Pożyczone**.
Matching ignores case and Polish diacritics. **Historia** shows newest entries
first and matches authors when the associated book is still in the collection.
Tap the selected genre or **Wszystkie gatunki** to change the filter or open
**Zarządzaj gatunkami**.

## Android manual backup

Open **Pomoc → Kopia zapasowa** and choose **Eksportuj kopię zapasową** to save
one `.mlbak` file in an Android document location you choose. To recover a
library after reinstalling or changing devices, use **Przywróć kopię zapasową**
and confirm the replacement. The unencrypted file can contain personal data.
Store it somewhere you can access after uninstalling the app.
[Backup format, recovery and limitations](docs/manual_library_backup.md)

## Offline SMS loan messages

**Pożyczone** offers **Skanuj kod QR**, **Dodaj z SMS** and **Dodaj ręcznie**
above one borrowed-book list, separate from owned books. Use **Pokaż kod QR**
on the owner's device and scan it from **Pożyczone**. If the camera is
unavailable, return to **Pożyczone** to retry, import an SMS, or enter the
details manually. Readable Polish SMS
imports have an editable preview and explicit save. Manual entry works offline
without an owner account or app. SMS contains no encoded loan codes. Prepared
messages offer **Kopiuj wiadomość** and **Udostępnij wiadomość**. Android's
share sheet lets you choose an app, where you send the message yourself.

Extensions use readable requests/responses; **Zmień termin zwrotu** changes only
the borrower's local agreed date. QR protocol v1 and existing revisions remain
compatible. SQLite v7 adds local SMS/manual entries and separate QR date overrides
without rewriting existing data. No verified Google Play listing is configured;
the centralized optional `VERIFIED_GOOGLE_PLAY_URL` remains empty.
See [SMS and borrowed-book rules](docs/offline_loan_messaging.md) and
[v7 migration and rollback checks](docs/borrowed_schema_v7.md).



Local-first Flutter MVP for cataloging books and tracking lending.

## Gatunki (SQLite v6)

Add and Edit Book include **Gatunek** after condition. New books default to
**Bez gatunku**. The selector supports creating a custom genre without losing
the form. Book Details shows the saved genre.

**Zarządzaj gatunkami** is available in the genre selector. It shows book
counts, supports renaming, and confirms deletion. Removing a used genre assigns
its books to **Bez gatunku** atomically; books and lending data are preserved.
The reserved default cannot be renamed or removed. Names are trimmed, limited to
60 Unicode characters, normalized to NFC, and unique regardless of case.
**Bez kategorii** is retired and cannot be created.

Starter definitions: Fantastyka, Science fiction, Kryminał, Thriller, Romans,
Horror, Literatura obyczajowa, Literatura historyczna, Biografia i autobiografia,
Literatura faktu, Przygodowa. These may be renamed or deleted and are seeded only
on installation or upgrade, never on reopening. Fresh installs have no demo books.

The **Gatunek** library selector combines with title/author search, status and
both sorting modes.

SQLite v6 removes the unused `directory` column and introduces
`genre TEXT NOT NULL DEFAULT 'Bez gatunku'`, plus the `genres` registry
(`id`, `name`, unique `normalized_name`). All books upgrading from v1–v5
receive **Bez gatunku**: old directory values are deliberately discarded,
never converted or inferred. IDs, other metadata, timestamps, covers, history,
reminders, QR transfers, borrowed loans and SMS data remain intact.
See [genre migration and test evidence](docs/genres.md).

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
placeholders. Open Library search does not create accounts, write to remote
libraries or fetch descriptions.

API: [Open Library Search documentation](https://openlibrary.org/dev/docs/api/search).

## Camera permissions

Android camera permission is declared for scanning and cover photography and
requested when using those features. Gallery selection uses the system picker,
without broad storage permission. Notification authorization is requested only
after reminder opt-in. See the [Android permission audit](docs/android_release.md#permissions-and-components).

## Help and borrowing guidance

Open **Pomoc** beside the library heading for **SMS i komunikacja o wypożyczeniu**
and **Wypożyczenia i synchronizacja danych**. Help explains operator charges,
manual SMS sending, unverified delivery and identity, and separate local loan
copies. **Samouczek — 7 slajdów** remains available without changing onboarding
completion. The separate **Pożyczone** collection contains borrowed copies,
outside the user's owned books. Operational screens retain action confirmations,
QR trust warnings and actionable errors.

See [Task 23 validation and before/after screenshots](docs/loan_ui_help_cleanup.md).

## Owner name in QR invitations

In **Pokaż kod QR**, choose **Edytuj nazwę właściciela** and enter an optional
**Właściciel**, e.g. Jan Kowalski. It is saved locally and reused for future QR
invitations; edit or clear it at any time. Names are trimmed, limited to 120
characters (UTF-16 units), support Polish letters and reject controls/newlines.
No account, internet connection or contact information is needed.

After import, the preview, **Pożyczone** list and details show the saved name;
older unnamed invitations show **Właściciel: Nie podano**. A changed name advances
the QR revision while preserving IDs and the original borrowing date. Borrowers
must import the new QR explicitly. The name is unverified user-provided information.
The readable invitation includes the saved owner name when available. See
[QR protocol and schema v8](docs/offline-loan-protocol.md).

## Book history

In Book Details, **Historia książki** appears below the primary action, such as
**Oznacz jako zwróconą**, and above **Usuń książkę**. It starts with the five
newest events. **Pokaż więcej** loads up to ten older events at a time, until
you reach the start of the history. Returning a book, extending a loan, or
changing the return date resets the view to the latest five events.

## Change return date

For a borrowed book, Book Details shows the saved return date or
**Brak terminu zwrotu**. Use **Zmień termin zwrotu** to select today or
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
