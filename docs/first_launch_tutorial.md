# First-launch tutorial (Android)

The Android root opens TutorialGate before constructing LibraryShell. The
shared_preferences boolean tutorial_completed_v1 is independent of SQLite,
book counts and notification settings. Only Zakończ writes it. Keep this key
stable across upgrades. Missing preferences mean a fresh installation.
Preference read failures bypass onboarding for that launch so the library remains
accessible. Write failures show a Polish retry message and keep the last slide open.

Android Back moves to the preceding page and stays on page one during onboarding.
There is no early dismissal. Help uses a separate route, starts on page one, and
can close with Android Back, the close icon, or Zakończ without accessing preferences.
The Pomoc button sits beside the heading on the main books list.

Content is the ordered tutorialSlides list. Add future metadata there after the
corresponding feature merges. Task 19 is already present in base main via PR #14
(commit 5aff32d); the QR page describes its offline export/import behavior.
Task 20 adds no slide in this task.

## Reproducible widget evidence

Run flutter test test/tutorial_test.dart.

| Evidence | Assertion |
| --- | --- |
| First launch and restart | Welcome appears with missing flag; finishing enters library; remount bypasses tutorial |
| Polish content | All six titles and descriptions compared verbatim in order |
| Navigation | Swipe, Dalej, Wstecz, disabled first Back, last-page-only Zakończ |
| Android Back | Moves to prior page, cannot dismiss first-launch page one |
| Help | Production TutorialHelpButton reopens at page one; all three exits restore previous route and its existing content |
| Persistence | Fresh LocalTutorialPreferences instance reads stored completion; unrelated preference preserved |
| Failures | Read failure reaches library; write failure stays on tutorial and supports retry |
| Layout | All six pages at 320×480 and text scale 2; resize to 480×320 preserves last page with no overflow |
| Permissions | Traversing onboarding makes no calls to camera, notification or permission channels |

These are widget assertions, not device screenshots. Device TalkBack review and
OEM-specific font/display sizes remain manual QA. No online artwork, new Android
permissions, example books, database migrations or backend services are introduced.
