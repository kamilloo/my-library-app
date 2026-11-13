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
Help uses a separate route, starts on page one, and can close with Android Back,
the close icon, or Zakończ. The Pomoc button sits beside the main books list heading.

## Seven-slide sequence

1. Witaj w Mojej Bibliotece!
2. Dodawaj książki
3. Zarządzaj wypożyczeniami
4. Udostępniaj kod QR
5. Proś o przedłużenie
6. Pilnuj terminów zwrotu
7. Twoja biblioteka, Twoje zasady

Content is the ordered tutorialSlides metadata list. Task 19 is represented by
the offline QR export/import page. Task 20 is now represented by the SMS extension
page, directly after QR, using Icons.sms_outlined. The original six slides retain
their text and icons.

The SMS workflow is local-first and manual: the borrower prepares an extension
request, Android opens their SMS app, and they send it manually. The owner imports
the request and explicitly approves or rejects it, then can prepare an SMS decision.
The borrower manually imports an approved confirmation to update their local date.
There is no automatic sending, SMS reading, synchronization, delivery guarantee,
automatic approval, cryptographic sender verification, Firebase or push integration.

## Reproducible widget evidence

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
