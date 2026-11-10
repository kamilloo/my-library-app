# Android V1 QA checklist

## Execution record

Repository: kamilloo/my-library-app. Preparation date: 2026-11-10.
Target: Android only. No Android device/emulator was connected (`adb devices -l`
returned an empty list; Flutter doctor listed Linux/Chrome only). **No
physical-device scenario below is marked passed.** Do not infer device delivery,
installation or upgrade success from a host build.

| Evidence | Environment | Status |
| --- | --- | --- |
| Unit/widget/SQLite regression suite | Ubuntu 22.04, Flutter 3.47.5 / Dart 3.13.4, SQLite FFI, fake HTTP/notifications, temporary files | 194 tests pass |
| Formatting and analysis | Same host | Pass |
| Clean debug APK compilation | Android platform 37.0; JDK from Android Studio; Gradle 9.3.1 | Pass |
| Release APK/AAB packaging and signatures | Existing private local signing configuration; no key generated | Both build; APK verifies, AAB jar verified and bundletool validates; JDK 25 stream-order warning requires release review |
| Packaged APK identity/permissions/components | Android SDK tools, host | Pass: com.kamilloo.mylibrary, 1.0.0+8, API 24/36; no AD_ID or broad storage; signature evidence in release record |
| Missing-credentials APK/AAB guard | Both Gradle release tasks, explicitly empty signing environment | Pass: both rejected with the intended credentials error |
| Physical install, launch, upgrade, notification delivery | No connected Android device, rechecked after laptop restart | Pending |

Use a new execution row for **every executed device test**, including failures.
Required fields: case ID, device model, physical/emulator, Android/API, OS build
fingerprint, app version/code, commit, signing certificate SHA-256, execution
date/time/timezone, result (PASS/FAIL/BLOCKED), evidence, tester and notes.
Record before/after database snapshots privately; borrower information must not
be posted in public PR artifacts. No device result rows exist yet.

Required device coverage: one physical Android 13+ device and at least one other
supported API level (minimum API 24). Include a 16 KB page-size device/emulator
for native compatibility, labeled separately from physical delivery tests.

## Device cases — all PENDING

### Install, upgrade and lifecycle

| ID | Procedure and expected result | Status |
| --- | --- | --- |
| A01 | Fresh install intended com.kamilloo.mylibrary identity; launcher label Moja Biblioteka, icon/adaptive masks, launch without demo data or unsolicited permission prompts | Pending |
| A02 | Install compatible-signed update over v1 fixture without clearing data; compare all books, metadata, covers, borrowers, original/due dates and history; schema becomes 3 | Pending |
| A03 | Repeat over v2 and v3 including reminder opt-in/disabled rows/IDs; no duplicate indexes, records or notifications | Pending |
| A04 | Restart, process death, background/foreground and reboot; saved collection immediately available; run integrity/FK checks on private copied DB | Pending |
| A05 | Verify offline launch/list/search/sort/filter/manual save; remote image placeholders; no dependence on Open Library connectivity | Pending |
| A06 | Small display, rotation during forms/dialogs/scanner, large font/display scale, keyboard; controls remain reachable and drafts do not corrupt saved records | Pending |
| A07 | Low storage during add/edit/cover copy/upgrade; Polish failure feedback, original rows/history/cover retained, retry possible | Pending |
| A08 | Backup/restore and device transfer respect exclusion policy; disclose that uninstall/clear-data/device replacement has no V1 recovery mechanism | Pending |
| A09 | Test release on 16 KB page-size runtime; verify all native libraries, camera/scanner/cropper and SQLite work | Pending |

For upgrade tests, retain the original installed app ID and compatible signing
identity. **Do not uninstall, clear data or downgrade a real user's collection.**
Use isolated test installations. Take a private backup of test DB and managed
covers before interruption/low-storage exercises. Debug-to-production certificate
changes are not an upgrade path; never solve incompatibility by clearing data.

### Cover files and picker recovery

| ID | Procedure and expected result | Status |
| --- | --- | --- |
| C01 | Gallery selection on API 24 and 33+: system picker/fallback, no broad storage prompt; crop/save/reopen uses managed support-directory copy | Pending |
| C02 | Cover photography: camera prompt on invocation; grant/deny/permanent denial; library and manual entry remain usable | Pending |
| C03 | Replace, remove and cancel edit/crop/picker; old saved cover persists on cancellation/failed save | Pending |
| C04 | Shared cover referenced by two books: delete one without removing the other's image | Pending |
| C05 | Missing file: placeholder without crash; restart/reboot/update preserve existing managed cover bytes and relative references | Pending |
| C06 | Kill app process while system picker/camera is open; reopen and verify retrieveLostData recovery, then crop/save/cancel; no accidental book insertion | Pending |
| C07 | Interrupt while cropper is open; saved book remains unchanged; unsaved draft may be lost, no user-owned file deletion | Pending |

### Scanner and metadata

| ID | Procedure and expected result | Status |
| --- | --- | --- |
| M01 | Camera opens only after explicit scanning; grant/deny/permanent denial/cancel; Polish fallback feedback | Pending |
| M02 | Scan ISBN-10 and ISBN-13; invalid checksum/unsupported barcode handled; manual entry always available | Pending |
| M03 | Manual ISBN: empty/invalid cause no HTTP; successful lookup; no match/offline/timeout/HTTP error and retry retain draft | Pending |
| M04 | Search title-only, author-only, combined and Polish characters; covers/placeholders/year, next pages stop at five pages/100 results | Pending |
| M05 | Search selection fills appropriate fields; uncertain edition leaves ISBN alone; cancellation/pending stale responses cannot replace newer edits | Pending |
| M06 | Existing title/author/local cover require confirmation to replace; correction remains editable; save is explicit and creates one record | Pending |
| M07 | Equivalent/existing ISBN add/edit rejected with Polish feedback; self edit and blank ISBN allowed; no changes to saved loans/history from search | Pending |
| M08 | Metadata requests contain only intended ISBN/title/author/cover query data, never borrower/history; inspect separately from existing ML Kit SDK diagnostic traffic and document Data safety | Pending |

### Loans, dates and history

| ID | Procedure and expected result | Status |
| --- | --- | --- |
| L01 | Available→borrowed→returned→borrowed by another person; original loan date stable within each loan, new opt-in required | Pending |
| L02 | Give away available and borrowed books; status filters/count/search/sort accurate; due date cleared and history correct | Pending |
| L03 | Add/earlier/later/clear return date; no-op makes no event; reject past date and nonborrowed books | Pending |
| L04 | Extend +7/+14/+30 or custom, including overdue/month-end/leap/DST; calculate from saved term; reject unchanged/earlier/still-overdue result | Pending |
| L05 | Repeated taps and stale dialogs reject obsolete source loan; borrower, original borrowing date, metadata/cover preserved; exactly one event per success | Pending |
| L06 | Details/list refresh immediately; book history excludes other books, newest first, global History retained; deleting follows cascade policy | Pending |

### Reminders

| ID | Procedure and expected result | Status |
| --- | --- | --- |
| N01 | Defaults off; absent borrower/date/past 09:00 ineligible; enabling asks permission only when needed | Pending |
| N02 | Android 13+ permission grant/deny/rationale/settings; Android 8+ Terminy zwrotu channel; deny/block/revoke does not undo loan writes | Pending |
| N03 | Disable channel or global notifications, then restore and resume; saved opt-in recovers with stable ID and no duplicates | Pending |
| N04 | Future date delivery around local 09:00 in foreground/background/process termination; Polish text, white icon and private lock-screen display | Pending |
| N05 | Date change/prolongation replace same ID; clear/return/give/delete/disable cancel; reborrow starts off | Pending |
| N06 | Restart/reboot/package update recover pending reminders with stable IDs; no prompt during automatic reconciliation | Pending |
| N07 | Change timezone/DST, resume and inspect new 09:00 schedule; closed app retains old timezone until resume; no immediate firing for past dates | Pending |
| N08 | Doze/battery saver/OEM restrictions and force-stop; record delays, reopen to reconcile; no exact-time guarantee | Pending |
| N09 | More than 60 enabled loans: nearest 60 pending, refill on resume; failures for one ID do not erase unrelated valid reminders | Pending |

Notifications use **inexactAllowWhileIdle**. A host/fake backend cannot prove
physical delivery, and 09:00 is not an exact alarm promise.

## Release gates

Confirmation of the intended production certificate and Play signing setup,
JDK 17/internal-track review of the documented AAB signature warnings, real
installed-upgrade tests, physical notification delivery, private-data loss
disclosure, privacy policy/listing/Data safety, Play internal testing and final
version-code checks remain developer release gates. Do not publish on the basis
of this checklist's existence. Record evidence first; no Play Console access or
publication has been performed.
