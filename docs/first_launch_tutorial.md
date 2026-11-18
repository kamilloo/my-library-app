# First-launch tutorial (Android)

The Android root opens TutorialGate before constructing LibraryShell.
The shared_preferences boolean tutorial_completed_v1 remains unchanged and is
independent of SQLite, book counts and notification settings. Existing users who
completed the six-slide tutorial continue directly to their library after updating.
New installations receive all seven slides. Only Zakończ during mandatory onboarding
writes the flag. Help never reads or writes it.

Preference read failures bypass onboarding for that launch so the library remains
accessible. Write failures show a Polish retry message and keep the last slide open.

Android Back moves to the preceding page and stays on page one during onboarding.
There is no early dismissal. Existing users can reopen all seven pages through Pomoc.
Pomoc opens a separate, scrollable guidance page with SMS and local borrowing sections.
Its Samouczek — 7 slajdów button reopens the tutorial at page one. The manual tutorial
closes back to Help with Android Back, the close icon or Zakończ. Help returns to the
unchanged library with Android Back. No preference is read or written by these routes.

## Seven-slide sequence

1. Witaj w Mojej Bibliotece! — optional owner name
2. Dodawaj książki
3. Zarządzaj wypożyczeniami
4. Pokazuj kod QR
5. Proś o przedłużenie
6. Pilnuj terminów zwrotu
7. Twoja biblioteka, Twoje zasady

Welcome offers **Twoje imię i nazwisko**. The app saves it locally on **Zakończ**
and preserves any existing owner name. If left blank, the next confirmed loan
asks for a name before saving. Canceling leaves the loan untouched. The shared
SQLite preference `qr_owner_name` supplies the **Właściciel** display label in
new QR invitations and readable loan-information SMS previews. It stays on the
device until the user shares loan information and carries no identity verification.
To change or clear it, open **Pokaż kod QR**, choose **Edytuj nazwę właściciela**,
then save the new name or an empty field. No account, internet or contact access
is required.

Content is the ordered tutorialSlides metadata list. Task 19 is represented by
the offline QR export/import page. Task 20 is represented by the SMS extension
page, directly after QR, using Icons.sms_outlined. The QR copy now calls the separate
borrowed collection Pożyczone; the SMS copy explicitly describes manual sending.

The SMS workflow is local-first and manual: the borrower prepares an extension
request, copies it or chooses an app from Android's share sheet, and sends it
manually. The owner reads
the request and uses the correct book's management actions to approve or reject it,
then can prepare a readable SMS decision. The borrower chooses Zmień termin zwrotu
and explicitly confirms the agreed local date. Pożyczone also supports Dodaj z SMS
with editable preview and Dodaj ręcznie alongside QR scanning.
There is no automatic sending, SMS reading, synchronization, delivery guarantee,
automatic approval, cryptographic sender verification, Firebase or push integration.

## Reproducible widget evidence

The Task 18.1 / PR #17 results below are a historical validation snapshot, not a
new Task 21 run. Current [canonical Android V1 scope and release gates](MyLibrary_Version_1_Updated_Specification.txt)
separate source implementation, automated results and pending physical QA.

Run flutter test test/tutorial_test.dart. Task 18.1 validation passed: all 282
unit/widget tests, flutter analyze, formatting checks, debug APK build and
git diff --check. The tutorial suite includes the fifth-slide widget evidence below.

| Evidence | Assertion |
| --- | --- |
| Polish content | All seven titles, descriptions and icons compared in order; SMS at index 4 |
| Fifth slide | SMS title, full description and icon render at 5 / 7 with Strona 5 z 7 semantics |
| Navigation | All seven pages swipe; Dalej, Wstecz and Android Back work around SMS; seven dots; last-page-only Zakończ |
| First launch and restart | Missing flag shows welcome; finishing enters library; remount bypasses tutorial |
| Existing users | A stored tutorial_completed_v1=true bypasses the seven-slide tutorial |
| Help | Reopens at page one; traverses all seven pages; all three exits preserve previous route and content without preference writes |
| Persistence | Fresh LocalTutorialPreferences reads completion; unrelated preference preserved |
| Failures | Read failure reaches library; write failure supports retry |
| Layout | All seven pages at 320×480 and text scale 2; resize to 480×320 preserves page seven without overflow |
| Permissions | Traversing onboarding makes no calls to permission, camera, notification, reminder or SMS launcher channels |

These are widget assertions, not device screenshots. Device TalkBack review and
OEM-specific font/display sizes remain manual QA. No online artwork, new Android
permissions, example books, database migrations or backend services are introduced.
