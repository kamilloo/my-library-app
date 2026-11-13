# Offline loan messages (Android, protocol v1)

All message preparation and SQLite operations work offline. Android opens the
user's SMS composer using ACTION_SENDTO, a smsto: URI and sms_body. The user
reviews the recipient/body and presses Send. Android sharing (ACTION_SEND,
text/plain) and **Kopiuj wiadomość** remain available when no SMS app is installed
or a platform launch fails. A successful launch only means the composer opened;
cancellation and delivery are not reported. SMS may incur charges and is not
end-to-end encrypted. No real messages are sent by automated tests.

## Workflow

1. Owner confirms a loan as before. In its details, **Wyślij informacje SMS**
   opens the message workflow. Preparing/canceling SMS never undoes the loan.
   An optional recipient may be typed without accessing contacts.
2. The invitation contains readable Polish text and the same v1 invitation code
   as **Pokaż kod QR**. Borrower copies only the code into **Pożyczone od innych**
   → **Wklej kod wypożyczenia** and explicitly confirms import. No verified Play
   listing is configured, so no installation URL is included. Installation does
   not preserve an invitation automatically; retain the SMS and paste afterward.
3. Tap a borrowed book to open its messages, then **Poproś o przedłużenie**.
   Presets add 7/14/30 calendar days to the locally stored due date, never today.
   With no date, presets are disabled and a custom future date is required.
   Dates must be after both the old date and today. **Przygotuj prośbę SMS**
   saves a separate local request; it never changes the actual due date.
4. Composer launch leaves the request **Przygotowana**. Only a separate,
   explicit declaration **Zapisz, że wysłano prośbę** can change it to
   **Oczekuje na odpowiedź (dostarczenie niezweryfikowane)**.
5. Owner opens the active book's **Odczytaj prośbę o przedłużenie**, pastes only
   the request code and reviews book, borrower, existing/requested term and ID.
   Preview is read-only. The sender is unverified; a pasted code is not evidence
   of identity or ownership. Approval/rejection requires a separate button.
6. **Zatwierdź przedłużenie** repeats instance/date/revision checks under SQLite's
   write lock in the existing extension transaction, preserves all metadata and
   reminder opt-in, adds one loan_extended event and saves the decision atomically.
   Reminders reconcile after commit. Rejection saves only a separate decision.
7. Owner can review the prepared decision and choose to open SMS, copy or share.
   Saved decisions can be reopened on this loan; **Wyślij potwierdzenie SMS**
   reuses the exact code without another extension. Failed/canceled composition
   does not undo a committed extension.
8. Borrower selects **Wklej potwierdzenie przedłużenia**, reviews old/new dates
   and the authenticity warning, then **Zastosuj nowy termin**. Import updates
   only the matching local borrowing record and its matching request status,
   transactionally. Duplicate exact confirmations are no-ops, including after a
   newer confirmation. Conflicting IDs, wrong instances, stale dates/revisions
   and replays under new IDs are rejected.

The owner's SQLite record is authoritative for the actual loan. A borrower can
remain on an older date indefinitely until explicitly importing a confirmation
or a newer v1 invitation. There is no server, account, background synchronization,
push delivery or automatic SMS inbox access. Confirmation can be applied without
a locally recorded request if its expected loan/date/revision match.

## Envelope and fields

Codes retain Task 19's prefix `moja-biblioteka:`, followed by unpadded
base64url of UTF-8 JSON. Input is bounded to 2400 characters before decoding.
Copy the standalone code, not the whole readable SMS. Long Polish messages may
be charged as multiple carrier SMS segments. Base64 is encoding, not encryption.

Existing `loan_invitation` v1 fields/encoding remain unchanged and interoperate
with QR/manual import. The invitation parser intentionally does not accept
extension messages: use their specific import workflows.

New types: `extension_request`, `extension_approved`,
`extension_rejected`. All use:

| Key | Meaning |
| --- | --- |
| p / v / t | moja-biblioteka / integer 1 / message type |
| id | Stable unique request ID (at most 80 characters) |
| loan / book | Loan-instance UUID and owner book ID (at most 80 each) |
| due | Expected previous due date, YYYY-MM-DD, or null |
| new_due | Requested/approved date, YYYY-MM-DD |
| revision | Expected invitation revision, positive bounded integer |
| issued | Request or decision timestamp in canonical UTC ISO-8601 |
| new_revision | Approval's new positive revision; null for other types |

Calendar dates are validated strictly (1900–2200). New dates must exceed old
dates; requests also undergo Task 14's future-date validation on preparation and
owner decision. Unsupported versions/types, oversized/malformed encodings and
invalid fields fail with Polish feedback before any mutation. Native message
bodies are limited to 4000 characters, phone input to 40. No arbitrary links
are followed or executed.

Revision advances when an already-exported loan's date changes, in the same
transaction, even if the date is later changed back. Owner decisions recheck
the current authoritative date and active instance against the exported revision.
A new lending period gets a new instance ID. Borrower imports never rewrite
owned books or authoritative loan-history events.

## Local storage and privacy

Schema v5 adds only `loan_messages` and `loan_contacts` to the private
SQLite `my_library.db` (sqflite's Android app-private databases directory).
Existing books/history/reminders and v4 transfer rows are preserved by migration.
Messages store role + request ID, loan ID, encoded request, encoded decision and
local status. Owner and borrower roles use distinct namespaces, including when
both are exercised on the same device. Decisions are retained as replay
tombstones separately from loan history during normal return and re-lending.
Explicitly deleting a borrowed record atomically removes its borrower-role
messages and saved contact, without changing owner-role or unrelated data.
Deleting an owned book atomically removes owner-role messages, contacts and
transfer snapshots for all its current and historical loan instances, including
legacy exported loans. Borrower-role copies remain independent. Reimporting a
deleted borrowed record starts without its former messages/contact. Uninstall
or clearing app data also deletes this local information.

An optional borrower/owner phone number is stored in `loan_contacts` keyed by
role and loan ID **only** after **Zapisz numer tylko na tym urządzeniu**. Saving
an empty number removes it. Typing a number or opening SMS does not save it.
The phone is passed only as the SMS recipient, never in QR codes, readable
messages or shared payloads. No contacts access or permissions are requested.
Messages contain only relevant book title, dates and protocol identifiers,
not descriptions, covers, complete history, filesystem paths or unrelated rows.
Existing borrower names, numbers and loan history are never provided to AdMob;
no advertising implementation changed. No new network or Firebase dependency,
SMS/contacts permission, incoming link handler, or release logging was added.
Existing Android backup exclusions continue to apply.

Neither requests nor confirmations have signatures or trusted key exchange.
An attacker can forge a syntactically valid matching code. User review is
mandatory; IDs/revisions prevent accidental/replayed changes, not impersonation.
Verify decisions with the other person when needed. Copies in SMS apps,
clipboard and chosen share destinations are outside this app's private storage.
No recovery/synchronization is promised after app data loss.

## Verification and physical-device QA

The 270-test result below is the historical Task 20 / PR #15 run, not a new
Task 21 result or current suite total. Later tutorial PRs record 280 and 282 tests;
see [canonical evidence and scope](MyLibrary_Version_1_Updated_Specification.txt).
All native/device cases remain pending until executed.

Host validation for Task 20: dependency resolution, formatting (including the
no-change check), analysis, **270 Flutter tests** and debug APK build passed.
This includes 10 deletion/privacy regressions for role isolation, historical
instances, reimport, rollback, cover cleanup and reminder reconciliation.
GitHub quality-checks/android-build results and final commit are recorded in the PR.
No real SMS or physical-device delivery test was executed.

Automated Flutter tests mock the MethodChannel: they never launch or send SMS.
SQLite tests exercise independent owner/borrower stores, strict parsing, v4→v5
upgrade, v1–v3 regression migrations, approval/rejection, rollback, opt-in
preservation, duplicate/stale IDs, read-only previews and file-backed restart.
Widget tests cover presets, absent dates, review, explicit sent declaration and
copy fallback. Native ACTION_SENDTO behavior still requires device QA.

Required before release (all device cases pending until executed):

- Two physical Android phones, one API 33+ and another supported API (24+).
  Record device/OS/app version/commit/tester and result, without public personal data.
- Default Google Messages and an available OEM SMS app: recipient/body including
  Polish characters and full code; user must press Send. Review multipart charges.
- Back/cancel composer and share sheet: no rollback of owner loan/approval,
  no automatic pending/sent/delivered status.
- Device without SMS handler (e.g. tablet): useful Polish failure; copy/share
  work; browsing and manual import stay usable. Deny/disable share targets too.
- Two-phone invitation → manual import → request → owner paste/approve →
  confirmation → borrower paste/apply; compare dates and exactly one history
  event, reminder opt-in and refreshed schedule. Repeat with reject.
- Change/return/reborrow/delete the owner's book after preview; stale approval
  must fail, and an old confirmation must not change a newer local date.
- Resend the saved confirmation after restart, import twice, then accept a newer
  one and replay the old one. No extra event or date regression.
- Airplane mode prepares all codes locally. Carrier delivery depends on service;
  no network synchronization occurs on reconnect. Do not infer delivery.
- Kill/restart either app during composer or after decision; persisted requests,
  decisions, contacts and imports survive; unsaved text drafts may be lost.
- Inspect final APK permissions: no SEND_SMS, READ_SMS, RECEIVE_SMS,
  READ_CONTACTS or WRITE_CONTACTS; no SMS receiver or background sender.
