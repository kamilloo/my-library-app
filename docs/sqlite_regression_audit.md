# SQLite regression audit — Android V1

## Current state versus historical audit

The audit below is the **Task 11 / PR #12 historical snapshot** (schema v3,
194 tests), retained without claiming a new run. Active source now opens
**my_library.db schema v6 in PR #19**, with nine tables and v1–v5 → v6 upgrades.
Task 22 intentionally replaces directory with genre, assigns all old books
Bez gatunku without inference, and adds the persistent genres registry. All other
book data and linked tables are preserved; see [genre migration](genres.md).
See [canonical schema and status](MyLibrary_Version_1_Updated_Specification.txt),
[Task 19 transfer additions](offline-loan-protocol.md) and
[Task 20 messages/contacts](offline_loan_messaging.md). Current migration tests
assert v6 even where historical test descriptions still mention v3 reopening.
Later test-run snapshots are recorded in the canonical specification; installed
Android upgrades remain unverified until device QA is recorded.

## Scope and validation

Task 11 audits the existing local database, repository, covers, metadata imports,
and reminder integration. No schema version, production database filename, table,
dependency, or platform configuration was changed.

Verified locally: dependency resolution, formatting (including no-change check),
Flutter analysis, **194 passing tests**, Android debug APK build, and
`git diff --check`. Tests use SQLite FFI with isolated memory/file databases,
temporary cover directories, mocked HTTP, fake notifications, and controlled
clocks. Trigger-injected failures exercise actual SQLite transaction rollback.
These results do not substitute for an installed Android application upgrade.

## Schema at the Task 11 audit (historical v3)

Version: **3**. Production location remains
`join(await getDatabasesPath(), 'my_library.db')`.
Dates/timestamps are ISO-8601 TEXT; application IDs are UUID strings.

### books

| Column | SQLite definition |
| --- | --- |
| id | TEXT PRIMARY KEY |
| title, author | TEXT NOT NULL |
| description | TEXT NOT NULL DEFAULT '' |
| cover_url, barcode | TEXT, nullable |
| condition, directory, status | TEXT NOT NULL |
| borrowed_by, borrowed_date, return_date | TEXT, nullable |
| created_at, updated_at | TEXT NOT NULL |

The partial unique index `idx_books_barcode` covers non-NULL barcode values.
Multiple books without a barcode are allowed. Description and directory storage
are preserved; this audit adds no management features for either field.

### history

| Column | SQLite definition |
| --- | --- |
| id | TEXT PRIMARY KEY |
| book_id, book_title, action, timestamp | TEXT NOT NULL |
| detail | TEXT, nullable |

`book_id REFERENCES books(id) ON DELETE CASCADE`. Deleting a book deletes its
history, matching established behavior. Metadata edits retain history and its
original title snapshots. `idx_history_book_timestamp` indexes
`(book_id, timestamp DESC, id DESC)`. Book Details reads only that book's newest
50 events with deterministic ID tie-breaking. Global History behavior is unchanged.

### return_reminders

| Column | SQLite definition |
| --- | --- |
| id | INTEGER PRIMARY KEY AUTOINCREMENT |
| book_id | TEXT NOT NULL UNIQUE |
| enabled | INTEGER NOT NULL DEFAULT 0 |

There is deliberately no foreign key to books: disabled rows for deleted books
are cancellation tombstones, retaining stable notification IDs for later recovery.
They are expected, rather than foreign-key violations. SQLite also creates its
primary-key/unique autoindexes.

Foreign keys are enabled on connection configuration. There are no SQL CHECK
constraints for statuses, date formats or reminder booleans. SQLite TEXT primary
keys do not themselves imply NOT NULL; normal application writes supply IDs.
These are application invariants, not guarantees for unsupported direct SQL writes.

## Creation and migration paths at the Task 11 audit (historical)

| Starting version | Behavior |
| --- | --- |
| Fresh | Create all three tables and current indexes |
| 1 | Add book-history index, then reminder table |
| 2 | Add reminder table |
| 3 | Reopen without rewriting rows or running upgrade DDL |

Sqflite runs the upgrade callback transactionally. No destructive database
initialization, delete-and-recreate fallback, or startup normalization is used.
Independent literal legacy SQL fixtures in
`test/fixtures/legacy_library_schema.dart` prevent migration tests from simply
reusing the current schema creator.

File-backed fixtures for versions 1, 2 and 3 contain all loan statuses, Unicode
metadata, descriptions, conditions, directory values, formatted/null ISBNs,
remote/local cover references, borrowers, original loan dates, due dates, and
history. Upgrades and two reopen cycles compare complete rows. Version 3 also
preserves enabled/disabled preferences, deleted-book tombstones, IDs 7/42/99 and
the AUTOINCREMENT high-water mark. Tests verify index/table stability,
foreign-key enforcement, cascade behavior, schema defaults, integrity_check and
foreign_key_check. Local managed cover bytes survive reopening.

## Verified defects and corrections

1. **Reading an empty library seeded demo books in debug builds.** This could
   repopulate a deliberately emptied collection. Removed runtime seeding; reads
   are now read-only.
2. **Loan operations wrote stale full-book snapshots.** A lend/return/give action
   could overwrite a newer metadata or cover edit. These operations now read the
   current row and update only loan fields inside a transaction, using the current
   title for history.
3. **Invalid/repeated loan transitions created history or changed records.**
   Snapshot and database source statuses must match before any writes. Returns
   require both to be borrowed; lending requires both to be available; giving
   permits matching available or borrowed states. For borrowed sources, borrower
   and original borrowing date must also match the active loan. Focused tests
   reproduce stale available return/give and stale borrowed lend attempts, verify
   unchanged rows/history/reminders on rejection, and preserve all valid flows.
   Missing/deleted books are rejected without resurrection.
4. **Equivalent ISBN-10/ISBN-13 values bypassed duplicate detection**, including
   concurrent saves and edits. A comparison-only key maps a valid ISBN-10 to its
   exact corresponding 978 ISBN-13. The duplicate check runs inside the write
   transaction as well as before cover copying. Stored ISBN values are not
   converted. The existing SQL unique index remains the exact-text backstop.
5. Some widget tests and repository timestamps used wall-clock time. Repository
   operations and date-picker validation now share the existing injectable clock;
   affected tests use fixed dates, including the picker current-date highlight.

No defect was reproduced in concurrent database initialization, so its
implementation was not changed.

## Repository integrity

Add, edit, delete, loan transitions and shared date/extension operations use
transactions for related database writes. Loan updates, history insertion and
reminder preference reset succeed or roll back together. Cover copying happens
before the transaction; safe cleanup follows success/failure. Native notification
synchronization follows commit and cannot roll back a successful loan change.

Lending requires an available book and borrower. Returning requires a borrowed
book and clears loan fields. Giving away permits available or borrowed books,
clears the due date and rejects already-given books; an existing borrowed book
retains its original borrowing date. Reborrowing resets reminder opt-in.

Change-date and extension operations reuse the existing shared transaction.
Unchanged date updates create no event. Extensions create exactly one
`loan_extended`, with no extra `borrowed` or `return_date_changed` event.
Repeated/concurrent requests cannot create duplicate successful events for the
same resulting date. Failed history writes roll back the associated date/loan.

ISBN editing excludes the current book from collision detection. Empty ISBNs
remain allowed. Lookup validation rejects invalid ISBNs before HTTP; the generic
ISBN/barcode storage field intentionally also accepts non-ISBN barcode values.
This audit does not turn barcode storage into ISBN-only storage. Exact equivalent
ISBN matching adds no fuzzy matching or new metadata provider.

## Regression coverage

| Area | Tests and evidence |
| --- | --- |
| Schema, upgrades, current reopen | history_migration_test; independent legacy fixtures; full row comparison and integrity checks |
| Transactions, lifecycle, concurrency | sqlite_repository_audit_test; library_repository_test; stale metadata/loan snapshots, concurrent equivalent ISBN saves, edit collision, repeated date writes, deletion races |
| Failure rollback | SQLite insert/update/history/preference failure triggers; no partial books/history/preferences or phantom events |
| History | book_history_test; migration/lifecycle tests; correct ID, ordering, retained snapshots, deletion cascade |
| Dates and extensions | change_return_date_test/widget; loan_extension_test/widget; first/clear/earlier/later/no-op, invalid status/date, overdue, presets/custom, month/leap/DST, UI refresh and repeated taps |
| Reminders | return_reminders_test; return_reminder_settings_test; fake backend failures, restart/recovery, stable IDs, permission changes, nearest-60/refill, reschedule/cancel and opt-in reset |
| Covers | cover_persistence_test; cover_picker_cleanup_test; cover_form_test; book_cover_test |
| Metadata and saving | open_library_service_test; open_library_search_service_test; manual_isbn_lookup_test; search_books_widget_test; search_books_persistence_test; add_book_screen_test; isbn_test |

Cover tests use temporary directories and cover reopen, replacement/removal,
shared references, canceled editing, missing images, failed copies/transactions,
cleanup failures, and deletion while a replacement copy is pending. Prior covers
are retained after failed replacement; staged copies are cleaned when possible.

Metadata tests mock network responses. Lookup/search selection does not insert
records; explicit save inserts one record, persists metadata after reopening and
uses repository duplicate protection. Selection/cancellation/failure does not
alter existing loans/history. Existing editing, scanner and manual-add flows
remain covered.

## Remaining limits and data-safety risks

- These tests exercise SQLite FFI, not Android sqflite through an installed
  application update. Real-device upgrade verification remains Task 12.
- Existing equivalent ISBN duplicates from older releases are preserved, not
  silently merged/deleted. New conflicting repository writes are rejected.
  The text-only SQL index cannot enforce the semantic comparison for external
  raw SQL writers.
- SQLite, filesystem and OS notifications cannot share a transaction. A process
  death between cover copy and database commit can leave an orphan file. Cleanup
  failures are best effort; no risky automatic cover garbage collector is added.
- Legacy absolute/cache cover paths may be unavailable after restore or a path
  change. References are preserved, and missing images have placeholders.
  Managed relative support-directory covers avoid depending on a fixed root.
- Notification synchronization failures may leave OS state stale until a later
  reconciliation. Fake-backend success does not prove physical delivery,
  reboot behavior or manufacturer battery-policy behavior.
- Historical ISO timestamps are not migrated to UTC. Mixed historical offsets,
  device-clock changes or timezone changes cannot be reconstructed into a
  guaranteed global event chronology from existing local timestamp strings.
- Global History remains unchanged; book history is bounded. Barcode semantic
  comparison scans stored barcode values; large-library performance requires
  device verification.
- Corrupt databases, unsupported future schemas, storage exhaustion and external
  SQL modifications are not automatically repaired. Backup/restore is outside
  this task.

No critical data-loss defect remains known in the tested supported paths. This
is bounded regression evidence, not a guarantee against device/storage failure.

## Task 12 — Android physical-device upgrade checklist

1. Prepare installed representative v1, v2 and v3 databases with every loan
   status, all historical actions, nullable/legacy barcodes, local/remote covers,
   and (v3) enabled/disabled reminders with known notification IDs.
2. Record rows/counts, cover bytes and actual app database/support paths. Install
   the update over the existing app using the same application identity and
   compatible signing identity; do not uninstall or clear application data.
3. Verify the unchanged my_library.db path, immediately available books, exact
   metadata/loan/history retention, indexes, foreign keys and integrity checks.
   Confirm current-v3 reopening does not duplicate anything or seed books.
4. Verify local covers offline, missing-file placeholders and shared-cover
   deletion safety. Verify historical absolute references on actual old installs.
5. Verify reminder opt-in and IDs survive; test permission revocation/restoration,
   due-date changes, extension, clearing, return/give/delete, restart/resume and
   reboot with no duplicate pending notifications.
6. Check timezone/DST changes, interrupted upgrade/low-storage recovery and a
   representative large collection on supported Android devices.

Physical-device upgrade/delivery checks have not been performed for this audit.
No iOS, signing setup or Google Play publication work is included.
