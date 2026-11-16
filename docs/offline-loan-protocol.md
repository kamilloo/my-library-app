# Offline lending protocol v1

Current scope: [canonical Android V1 specification](MyLibrary_Version_1_Updated_Specification.txt).
This document describes Task 19 invitations and its historical v3 → v4 migration.
The active database is **v8**: Task 25 adds local_preferences for the optional QR
owner name. Task 24 adds separate SMS/manual entries and local
QR date overrides without changing the invitation wire format or old QR rows.
Task 20 extension codecs remain for stored history compatibility; outgoing SMS is
now readable text only. See [offline loan messaging](offline_loan_messaging.md)
and [v7 migration](borrowed_schema_v7.md).
The invitation decoder still accepts invitations only. Historical Task 19 test
and migration statements below do not claim a new verification run.

Android devices keep independent local databases. This protocol needs no network,
accounts, Firebase, hosted endpoint or deferred deep links. Codes are untrusted
claims, not proof of ownership or identity. Preview confirmation always precedes import.

## Wire format

ASCII prefix `moja-biblioteka:` followed by unpadded Base64URL of a UTF-8 JSON object.
Maximum complete code length: 2400 characters. No cover bytes, borrower name,
paths, notification IDs, descriptions or library history are transmitted.

| Key | Meaning | Bound |
| --- | --- | --- |
| p | moja-biblioteka | fixed |
| v | integer protocol version | 1 |
| t | message type | loan_invitation |
| id | globally unique transfer ID, stable across revisions | 80 |
| loan | owner-generated globally unique loan instance reference | 80 |
| book | opaque owner-side book reference | 80 |
| title | book title | 240 |
| author | author | 160 |
| isbn | normalized validated ISBN, nullable | 13 |
| owner | optional owner display name, nullable | 120 |
| borrowed | original borrowing ISO-8601 date/time | 40 |
| due | nullable ISO-8601 return date | 40 |
| issued | UTC ISO-8601 issuance timestamp | 40 |
| revision | monotonically increasing integer | 1..2147483647 |

Dates retain the original borrowing time and the planned calendar date; issued
is UTC. Calendar comparisons use UTC calendar components so device time zones
do not change validation. Invalid calendar dates, overflow times and non-integer
versions are rejected.

String bounds are Dart UTF-16 code units. Required strings cannot be blank or
contain ASCII control characters. Dates are bounded to years 1900–2200 and a due
date cannot precede the borrowed calendar date. Unknown fields are ignored but
cannot bypass the overall payload bound. Unknown versions and message types fail
closed. The internal LoanTransfer model is separate from encoding and parsing.

The existing UUID lending history event supplies the stable loan-instance ID.
Returning and relending a physical book creates another event and another loan ID.
Opening the QR screen creates no book or history changes. A separate owner-side
snapshot stores the transfer ID, revision and issuance time. A changed title,
author, ISBN, owner display name or due date creates a new revision upon QR generation. Reopening an
unchanged invitation returns the same bytes. Existing v3 active loans receive a
UUID once at first QR generation, persisted in owner_loan_instances. This avoids
reconstructing identity from potentially tied history timestamps.

Task 19 reserved extension_request, extension_approved and extension_rejected for
separate validated models/dispatch using this envelope and stable loan reference.
Task 20 now implements those codecs and manual SMS transport; see
[offline loan messaging](offline_loan_messaging.md). This invitation decoder still
accepts invitations only. Automatic SMS sending remains unimplemented and is not
part of the manual transport design.

## SQLite v3 → v4

Forward-only additive migration creates:

- owner_loan_instances: book_id primary key with cascading ownership FK, unique
  loan_id; lending sets this atomically, return/giving clears it.
- loan_transfers: loan_id primary key, encoded owner snapshot.
- borrowed_loans: loan_id primary key, transfer_id unique, encoded validated
  metadata, revision, local_status (active by default).

Existing books, ISBN uniqueness, history, reminders and cover references are not
rewritten. All import, delete and snapshot writes use transactions. Borrowed rows
have no ownership foreign key and cannot be passed to owned-book operations.

Exact duplicate imports are no-ops. Higher revisions require the same transfer ID,
book reference and original borrowing time; issuance must not decrease.
The optional owner display name may change in a higher revision; it is metadata,
not an identity check. Old app versions can read v1 named invitations, but versions
before Task 25 may reject a name-changing update to an already imported loan.
Same-revision conflicts and stale codes are rejected. Unique transfer collisions
roll back. New loan instances remain separate even for the same physical book.
Deleting an imported row only deletes that device's row. Local status survives
updates. Deleted invitations may be imported again after explicit confirmation.

## Preferred owner name (Task 25)

On the QR screen, **Edytuj nazwę właściciela** opens the optional **Właściciel**
field (example: Jan Kowalski). Save trims surrounding whitespace; empty clears it.
The limit is 120 UTF-16 code units, matching v1. Polish characters are supported.
C0/C1 controls, DEL and Unicode line/paragraph separators are rejected, including
at the edges before trimming. No device/account/contact identity is read.

SQLite v7 → v8 only adds local_preferences(key primary key, value not null).
The qr_owner_name setting survives restart and is reused by future QR generation.
No old rows are rewritten at migration. Existing active snapshots refresh lazily
when generated, with stable IDs and original borrowing date, and revision +1 when
the name differs. Unchanged normalized names preserve the complete encoded bytes.
Date-only extension snapshots preserve their existing owner until QR generation.
Borrowers see the name after explicit import, or Właściciel: Nie podano if absent.
Names remain unverified claims. Phone contacts, SMS codecs, history and reminders
are unaffected. The SMS invitation dialog lets the user explicitly choose a name
for that message; leaving it empty uses Nie podano. Extension SMS does not
automatically include the QR owner name.

## Sharing and QA

User-initiated sharing uses Android ACTION_SEND with text/plain through the
bounded my_library/offline_loans method channel. No sharing plugin, SMS permission,
incoming link receiver or additional manifest component is needed. A native
sharing failure offers the copy-code fallback. Widget tests verify the shared
message, privacy boundaries and failure/copy behavior.

Share text explains the app requirement and manual import after installation.
There is no verified Play listing configured; no URL is invented. Users obtain a
trusted installer from the owner. Automatic app opening and deferred installation
routing are not implemented. Copy/paste and in-app camera scanning are fallback
paths. The QR is black on white with a quiet zone and medium error correction.

Widget tests exercise preview/cancel/confirm, owner confirmation and QR reopening,
camera denial and manual fallback, repeated detections, invalid-code retry,
background/resume, and QR rendering at 320px width.
Repository tests exercise offline SQLite writes, duplicates, conflicts, revision
ordering, rollback, separate instances and stable QR reopening. Existing migration
audits also run against schema v4 and preserve v1/v2/v3 collections.

Physical Android QA still required: two phones in airplane mode, Polish text,
long titles, missing due dates, camera denial/recovery, repeated detections,
rotation/background/resume, native sharing, and scanning on low brightness/small
screens. No automated test needs live HTTP or cloud access.
