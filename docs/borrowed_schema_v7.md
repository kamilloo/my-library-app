# SQLite v7 — Task 24

The v6→v7 upgrade only creates `local_borrowed_entries` and
`borrowed_due_overrides`. Existing tables, QR payloads/revisions/identities,
owner history, reminder intent, contacts, messages and genre data are untouched.
Fresh databases create the same schema. v1–v5 first execute their existing
forward migrations, including the v6 genre rebuild.

`local_borrowed_entries` has a local UUID primary key; an explicit CHECK-constrained
sms/manual origin; title, author, owner and borrowed date; nullable ISBN/due date;
and a unique nullable canonical source SMS. No owner-issued revision is stored.
Duplicate detection normalizes CRLF to LF and trims outer whitespace, with no
title/ISBN merging. Delete removes the source so it can be reimported intentionally.

`borrowed_due_overrides` has loan_id primary key referencing
borrowed_loans(loan_id) ON DELETE CASCADE, plus a required due date.
QR list/details use the override while protocol serialization retains the
original invitation. A newer invitation does not erase a locally agreed date.
Deleting QR clears the override in SQLite. SMS/manual dates live in their own rows.

The origin-aware repository deletion never deletes another origin with the same
identifier. Local saves/date changes never update `books`, owner history or reminders.

## Verification

Task 24 local validation on 2026-11-16 passed: flutter pub get;
dart format lib test; no-change formatting check; flutter analyze (no issues);
flutter test (357 passed); flutter build apk --debug; git diff --check.
This includes legacy v1–v5 upgrade regressions, populated v6 upgrade/reopen,
and the forced v7 migration failure/rollback/retry cases below.

`test/borrowed_migration_test.dart` starts with a frozen v6-compatible schema and
populated QR/messages/contact records. It verifies byte-identical old rows after
upgrade, saves both new origins, applies a local QR date, closes/reopens the file,
checks origins/dates and PRAGMA foreign_key_check.

The rollback case deliberately creates a conflicting second table. Failure during
v7 migration must roll back the first new table and user_version to 6, leaving all
old rows unchanged. After removing only the test fault, upgrade must succeed and
persist all three origins across restart. This is migration-transaction rollback,
not a supported binary downgrade. Existing v1–v5 regression migrations remain tested.

No destructive downgrade handler is added. Restore a pre-upgrade backup for an
older app; never reset the user's live collection. Real signed Android app-update
and physical-device SMS/camera QA remain release checks.
