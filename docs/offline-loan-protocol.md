# Offline lending protocol v1

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
author, ISBN or due date creates a new revision upon QR generation. Reopening an
unchanged invitation returns the same bytes. Existing v3 active loans receive a
UUID once at first QR generation, persisted in owner_loan_instances. This avoids
reconstructing identity from potentially tied history timestamps.

Future message types (extension_request, extension_approved, extension_rejected)
must use the same protocol/version/type envelope and stable loan reference, with
their own explicitly validated model and dispatch. V1 currently accepts invitations
only; extension transport and SMS automation are outside this task.

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
book reference, original borrowing time and owner; issuance must not decrease.
Same-revision conflicts and stale codes are rejected. Unique transfer collisions
roll back. New loan instances remain separate even for the same physical book.
Deleting an imported row only deletes that device's row. Local status survives
updates. Deleted invitations may be imported again after explicit confirmation.

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
