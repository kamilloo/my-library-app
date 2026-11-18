# Task 25 — owner display name

The QR screen offers **Edytuj nazwę właściciela** with the optional **Właściciel**
field and Jan Kowalski hint. Save reuses the normalized name across books and
restarts. Empty clears it. SQLite v8 adds only local_preferences; existing rows
remain unchanged. QR v1 remains the wire format with optional owner, bounded to
120 UTF-16 units and validated for control characters/newlines.

A changed name creates the next invitation revision, retaining transfer/loan/book
IDs and original borrowing time. Unchanged normalized values retain identical
payloads. Date-only extension transactions retain the old snapshot name until
QR generation. The borrower explicitly imports the refreshed code.

Old unnamed invitations still work. Apps predating Task 25 can read named v1
invitations but may reject a name-changing update for an already imported loan.
There is no automatic identity verification, account, contact lookup or network
request. The QR name is unverified information, never proof of legal ownership.

Welcome offers the owner name on first launch. If it was skipped or cleared,
the next confirmed loan asks for a name before saving. Readable loan-information
SMS previews use the saved name automatically, or Nie podano for unnamed loans.
Extension requests omit the owner label. SMS sending remains manual.

## Automated validation

Flutter 3.47.5 / Dart 3.13.4:

- Standard Dart format check and Flutter analysis: passed, no issues.
- Complete test suite: 387 tests passed (including 10 owner-name tests).
- Debug APK build: passed.
- Borrowed-list refresh now uses a void setState callback, avoiding a false
  save-error snackbar after successful imports; covered by the label widget test.
- owner_name_test.dart covers empty names, Polish text, trim/control/length
  validation, file-backed SQLite close/reopen persistence, v7 migration and
  rollback, stable and changed revisions, import/clearing, absent owner,
  unchanged history/reminders/messages/contacts, QR editing, borrower preview,
  list and details labels, and optional SMS name without encoded codes.
- Existing history, reminders, SMS, QR and migration regressions remain enabled.

## Screenshots

These are Flutter widget-renderer captures with Roboto, not device screenshots.
No Android device was connected; physical two-device scanning in airplane mode
and native SMS delivery remain release QA.

- [Owner input](screenshots/task25/owner-input.png)
- [Named QR](screenshots/task25/owner-qr.png)
- [QR import preview](screenshots/task25/import-preview.png)
- [Borrowed list](screenshots/task25/borrowed-list.png)
- [Borrowed details](screenshots/task25/borrowed-details.png)

Regenerate via the opt-in renderer hook in the owner-name widget tests:

```bash
OWNER_SCREENSHOT_FONT=/path/to/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf flutter test test/owner_name_test.dart --dart-define=OWNER_SCREENSHOTS=true
```

The normal test suite does not read host font files or write screenshots.
Final commit SHA and GitHub Actions results are recorded in the pull request.
