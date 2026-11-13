# Gatunki — Task 22

The Add/Edit Book selector appears after Stan and before Save. It defaults to
Bez gatunku, preserves the form during inline genre creation and selects the new
name. Details displays Gatunek. Zarządzaj gatunkami is reachable from the library
and selector, shows assignment counts, and requires explicit save/confirmation.
Counts use Polish forms: 1 książka, 2 książki, 5 książek; 12–14 and repeated
hundreds/tens follow Polish plural rules in both the list and deletion preview.
Rename/delete commit independently of the book form. Canceling that form does
not undo an already confirmed registry operation.

The owned-library selector offers Wszystkie gatunki, Bez gatunku and saved
genres, combined with title/author search, status and recent/A–Z sorting.
Renamed filters follow the stable registry ID; deleting the selected genre clears
the filter. The total collection count includes all owned books.

## Schema v6

books retains its 14 columns, replacing directory with
`genre TEXT NOT NULL DEFAULT 'Bez gatunku'`. Other columns remain id, title,
author, description, cover_url, barcode, condition, status, borrowed_by,
borrowed_date, return_date, created_at and updated_at.
The partial unique idx_books_barcode index remains.

genres has `id TEXT PRIMARY KEY`, `name TEXT NOT NULL`,
`normalized_name TEXT NOT NULL UNIQUE`. Names use NFC plus lowercase for the
unique key, trim outer whitespace, support Polish letters and up to 60 Unicode
scalars, and reject control characters/newlines. Repository validation and the
SQLite unique constraint both protect against duplicates.
Bez gatunku is a reserved virtual system entry; Bez kategorii is also reserved.

Starter definitions, seeded once on fresh install or upgrade:
Fantastyka; Science fiction; Kryminał; Thriller; Romans; Horror;
Literatura obyczajowa; Literatura historyczna; Biografia i autobiografia;
Literatura faktu; Przygodowa.
Users may rename/delete any starter. Reopening never reseeds. No demo books exist.

## Forward migration

Supported v1–v5 installations run their remaining older steps and upgrade to v6.
Android API 24 SQLite cannot reliably DROP COLUMN, so migration uses a rebuild.
onConfigure disables foreign keys before sqflite begins its upgrade transaction.
A new books_v6 copies every nonclassification column directly with SQL and assigns
Bez gatunku to every book. The old parent is dropped without cascade, the new
table takes its name, and explicit indexes/triggers are restored. Child references
continue to target books(id). PRAGMA foreign_key_check runs before commit.
onOpen re-enables foreign keys. Any failed DDL, insert, index recreation or
relationship check rolls back the transaction and user_version.

history, return_reminders, owner_loan_instances, loan_transfers, borrowed_loans,
loan_messages and loan_contacts are not rebuilt or rewritten. Task 19 QR and
Task 20 SMS protocols remain unchanged. No cover files are touched by migration,
rename or delete. Registry rename/reassignment/delete each runs atomically and
does not change lending state, timestamps, history or QR/SMS revisions.

## Legacy fixture audit

Before changes, nondefault directory values appeared in fixtures:
Shelf; Keep directory; Istniejąca półka; Istniejąca półka 0, 1 and 2.
These are discarded legacy classification metadata, never migrated into genres.
Runtime model fixtures now use a real starter genre (Fantastyka); frozen legacy
schema and migration fixtures retain directory to test the actual old format.
The migration tests also include a legacy Fantastyka value to prove even matching
starter names receive Bez gatunku rather than inferred assignments.

## Initial Task 22 validation (2026-11-13, historical snapshot)

flutter pub get, formatting and format verification, flutter analyze, all
318 automated tests (36 focused genre tests), flutter build apk --debug and
git diff --check passed locally. The debug APK is generated at
build/app/outputs/flutter-apk/app-debug.apk.

## PR #18 integration follow-up (2026-11-13)

PR #19 incorporates main at 8027a8fb92643b9ffdd811dbb5d93b43ee905c15,
including the canonical specification and preserved historical MVP/QA evidence.
Genre selection, creation, renaming, deletion and filtering are documented as
IMPLEMENTED in this PR; physical-device upgrade/accessibility QA remains pending.

After integration and the count-label fix, flutter pub get, strict formatting,
flutter analyze and the complete flutter test suite passed locally: **320 tests**.
Two new regression tests check singular/few/many/teen forms and the management
list/delete preview for 1, 2 and 5 books. The 318-test record above remains the
original feature snapshot. Final commit and rerun Android CI links are recorded
in PR #19. No protocol, loan-state, reminder or permission behavior was changed
by this follow-up.

## Automated evidence

- genre_migration_test.dart: populated v1–v5 upgrades, exact book metadata and
  timestamps, all seven linked tables, indexes/ISBN uniqueness, NOT NULL genre,
  exact starter registry, repeated reopen, foreign keys and failure rollback.
- genre_repository_test.dart: create/count, NFC/case duplicates, SQLite uniqueness,
  invalid/reserved names, scalar limit, missing genre checks, metadata-only edits
  in all three states, transactional rename/delete rollback and persistence.
- genre_widgets_test.dart: defaults/starters, inline creation retaining text,
  genre-only edit, Polish validation, used/unused delete confirmation,
  combined filtering/sorting/counts, rename/delete filter refresh (including
  changes made behind a canceled Add Book form without losing search/sort), and
  320×640 screen at 200% text.
- Existing tests retain loan, QR, SMS, history, reminders, covers and ISBN checks.

Physical-device migration and accessibility testing across Android versions
remain additional manual QA; automated SQLite migration tests use sqflite FFI.
