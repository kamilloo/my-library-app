# Borrowed books and readable SMS — Task 24

This replaces the previous encoded SMS workflow. QR protocol v1 remains unchanged.
Task 23 is already in main at cc1209e. No application publication is part of this task.

## Borrower workflows

**Pożyczone** shows **Skanuj kod QR**, **Dodaj z SMS**, and **Dodaj ręcznie**
above one list. **Wklej kod wypożyczenia** is a separate QR fallback.
Every entry opens the same details screen and can be deleted locally.
Entries never insert into the owned `books` table or affect genre management.

For SMS, paste the complete supported message, tap **Odczytaj wiadomość**,
correct any field in the preview, then **Potwierdź i zapisz**. Parsing alone
never saves. Manual entry uses the same fields and validation, works offline,
and requires no owner account or app. Polish date pickers use DD.MM.RRRR;
borrowing defaults to today and the due date may be absent.

Supported invitation:

```text
Moja Biblioteka — informacja o wypożyczeniu

Książka: Wiedźmin
Autor: Andrzej Sapkowski
Właściciel: Jan Kowalski
Data wypożyczenia: 14.11.2026
Termin zwrotu: 14.12.2026
```

An optional ISBN line contains a valid ISBN-10 or ISBN-13. Title, author and owner
are required (240, 160, 120 characters respectively). The owner enters their name
when preparing the outgoing invitation; this does not change QR identity data.
Old QR invitations without an owner display **Właściciel: Nie podano**.

The parser requires the exact Polish header and known labels, allows LF/CRLF
and blank lines, rejects duplicate/unknown fields, invalid calendar dates,
dates outside 1900–2200, due dates before borrowing, control characters and invalid
ISBN checksums. Input is limited to 3000 UTF-16 code units before parsing.
Missing borrowing date defaults to the repository clock's calendar day.
Missing due date stays unset. Missing title, author or owner is an error.
A single Google Play installation URL for com.kamilloo.mylibrary is accepted
only as a standalone trailing line, independently of the recipient build's URL
configuration. Other packages, websites, lookalike hosts, duplicate links and URLs
embedded in structured fields fail. This is one explicit template, not a
general conversation extractor. All parsed fields can be edited before confirmation.

## Extensions

The borrower selects **Poproś o przedłużenie** and a proposed date:

```text
Moja Biblioteka — prośba o przedłużenie

Książka: Wiedźmin
Właściciel: Jan Kowalski
Obecny termin zwrotu: 14.12.2026
Proponowany termin zwrotu: 21.12.2026
```

Preparing this text does not change the saved date. Requests contain no protocol
ID or encoded payload. The owner reads the human message and opens the relevant
owned book. Existing **Przedłuż wypożyczenie** and message-screen
**Zatwierdź przedłużenie** call the same extension transaction, preserving
owner history, instance checks and reminder reconciliation. A readable approval
contains the title and **Nowy termin zwrotu**. **Odmów przedłużenia SMS**
prepares a readable rejection with the unchanged term and does not mutate the loan.

The borrower chooses **Zmień termin zwrotu**, selects the agreed date and
confirms that this affects only the local device. There is no confirmation-paste
action, authentication claim or automatic synchronization. This applies equally
to QR, SMS and manual entries.

## Installation URL and SMS transport

All outgoing SMS use `withInstallationLink` and the single build configuration
`VERIFIED_GOOGLE_PLAY_URL`. It is empty by default. Configure it only after a
maintainer has verified the real public listing. Runtime validation allows only
HTTPS, the exact play.google.com host, /store/apps/details and exactly one
id=com.kamilloo.mylibrary parameter, without credentials, explicit port or fragment.
The package identity matches android/app/build.gradle.kts; recognizing it does
not assert that a public listing exists. URL validation cannot prove public availability. No URL has been invented or
configured in this task. Tests use a clearly isolated example fixture.
Missing/invalid configuration never blocks composition.

Android opens ACTION_SENDTO with smsto: and sms_body. The user chooses to send.
Copy and share remain available. Opening a composer is not proof of delivery;
SMS can incur operator charges and is not end-to-end encrypted. No automatic inbox
reading, sending, SMS permission, contacts permission, account or network is needed.
Optional recipient contacts remain local and are removed with their local record.
QR uses the existing borrower role; SMS/manual contacts use separate
borrower_sms/borrower_manual roles so coincident identifiers stay isolated.

## Database v7 and origins

- `borrowed_loans` remains byte-for-byte schema compatible with v6: original
  QR payload, transfer ID, loan ID, revision and local status are retained.
  Its membership means origin `qr`; no title/ISBN-based merging is introduced.
- New `local_borrowed_entries` stores a local UUID, explicit `sms`/`manual`
  origin, title, author, required owner, optional ISBN, borrowing/due dates and
  an optional unique canonical SMS source. IDs are generated only locally and
  are not protocol identities. There is no QR payload or owner revision.
- New `borrowed_due_overrides` stores only a QR record's local agreed due date,
  keyed to `borrowed_loans` with ON DELETE CASCADE. Changing it never alters the
  owner's invitation. A newer QR import retains an explicit local override.
- The list adapts all rows to a common view. Local views use empty protocol IDs
  and revision 0 as a nonprotocol sentinel; encoding them as QR throws.
  QR views retain their original protocol source when serialized.
- Exact SMS reimports are blocked after CRLF normalization and outer trimming,
  even if the first preview was corrected. Different messages and separate manual
  loans with the same ISBN are allowed. Identical real-world repeat messages
  cannot be distinguished: use manual entry for a separate legitimate loan.
  Deleting an entry also deletes its deduplication source.
- Deletion selects the origin as well as the identifier; a coincident QR/local ID
  cannot cause cross-origin removal. Owned books are never touched.

Migration is additive in sqflite's upgrade transaction: v6→v7 creates two tables;
v1–v5 follow existing migrations first. No old payload, history, contact, reminder
or genre is rewritten by the v7 step. Existing encoded extension data/codecs remain
for persistence compatibility and regression coverage; new UI does not import them
and no outgoing SMS embeds them. Earlier message history remains readable.

See [migration checks](borrowed_schema_v7.md) and the Task 24 test files.
Downgrade is not implemented: restore a pre-upgrade backup when returning to older
binaries. Do not clear the live database to downgrade.

## Limits

No sender authentication, delivery receipt, automatic synchronization or reminder
scheduling for the borrower's separate collection is implied. Owner-side reminder
behavior remains unchanged. Real SMS delivery and camera hardware still require
device QA. Parsing edited freeform messages is intentionally unsupported.
