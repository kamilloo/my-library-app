# Task 32 Android emulator QA

## Environment

- Disposable AVD `task32` on `emulator-5580`, model `sdk_gphone64_x86_64`, Android 14 / API 34.
- Android Emulator 37.2.13.0, Google APIs x86_64 system image at `system-images/android-34/google_apis/x86_64`, KVM acceleration, 2,560 MiB of guest RAM and SwiftShader graphics.
- Flutter 3.47.5, Dart 3.13.4 and Android Studio OpenJDK 25.0.4. Debug variant with the Android debug signing identity.
- Started from PR #29 at `538eb09e2eff100acd22b73e10832811290cf3da`. That revision installed successfully with KVM. The export/reinstall sequence used one production-entrypoint debug APK built with the staged journal fix. The follow-up APK at tested source commit `3c04d3b4f1471e925116214712e848100a14cfc2` adds cold-start reminder recovery and is used for the checkpoint retest.

## Fixture

The fixture ran the actual repository and reminder APIs on the disposable emulator using a temporary Flutter entrypoint. The production-entrypoint APK was installed over the fixture APK before any backup action. The temporary entrypoint and the debugger harness are outside the repository. Neither is part of the production APK. The QR data came from an owner invitation imported through the repository, without using the emulator camera.

| Book | Author | Genre | Expected state |
| --- | --- | --- | --- |
| Żółta Łódź | Świętosław Żak | Baśnie QA | Locally managed cover, active loan to Paweł Żółć, due 04.12.2026 |
| Źródło Rzeki | Grażyna Łoś | Podróże QA | Returned by Małgorzata Łąka, with a return history entry |
| Śnieg na Łące | Łukasz Ćma | Poezja QA | Available |

The preferred owner is Łucja Żuraw. QR borrowed data retains the owner due date and displays the local override of 06.12.2026. SMS and manual borrowed entries both use the fictional title Ćma z Łodzi and date 04.12.2026. The source had six history entries and one opted-in return reminder.

## Device results

| Check | Result |
| --- | --- |
| Boot, install and launch | `getprop sys.boot_completed` reported 1 and `ro.build.version.sdk` reported 34. Both initial installation and the same-APK reinstall succeeded. |
| Help | Tutorial above backup. SMS, synchronization, then backup instructions. Both backup actions were visible and back returned to Help. |
| Cancel export | Polish cancellation feedback appeared without a success message. |
| Export | Android's Downloads picker suggested `MojaBiblioteka-backup-2026-11-20.mlbak`. Save completed with Polish success feedback. The 1,017,842-byte ZIP passed inventory, size and SHA-256 checks. It held one database and one referenced cover. |
| Uninstall and reinstall | `adb uninstall` succeeded on `task32`. `stat` still found the original file in public Downloads. The same APK installed again and showed first-launch onboarding. |
| Cancel restore picker and confirmation | Each cancellation left the fresh application's SQLite snapshot identical to its baseline. |
| Confirm restore | With notification permission granted, restore displayed Polish success feedback and replaced the sentinel book already saved in the fresh app. All 13 application tables matched the archive when cover paths were compared by their file digests. |
| SQLite, covers and restart | `integrity_check` returned `ok` and `foreign_key_check` returned zero rows. After force-stop and relaunch the rows still matched, the cover rendered, and the Polish lending dates and names were visible. |
| Invalid archives | Plain text, truncated ZIP and format version 999 each produced the expected Polish rejection. After each selection, the SQLite and cover snapshot matched the valid archive. |
| Failed export | Temporarily hiding the fictional managed cover caused Polish export failure feedback. Returning the same file to its path left the SQLite and cover snapshot identical to the valid archive. |

The first emulator export on the original PR revision produced `document_failure` before the picker. The paused Dart isolate exposed a retained `my_library.db-journal` in the staging directory. Using DELETE journal mode for writable backup databases corrected that failure. On the journal-fix build, the application registered one system alarm and cached reminder ID 1 immediately after restore. Force-stop removed the system alarm while the cache still exposed ID 1, which prompted the cold-start reconciliation fix. With that fix installed, force-stop again removed the system alarm. Relaunch re-registered exactly one Android alarm at 09:00 Europe/Warsaw on 04.12.2026 using reminder ID 1. The SQLite and cover snapshot still matched the archive.

The host round-trip now exercises persisted loan transfers, owner instances, QR borrower state and due overrides, sent requests and decisions, loan contacts, and the two local borrowed origins through the repository. Concurrent-write tests hold a live SQLite repository write open during export and attempt a write during restore. Failure tests verify the previous rows and cover bytes and exercise a subsequent repository write. A PERSIST fixture covers the Android staging regression and a reminder test verifies one rearm without canceling or prompting.

## Interrupted restore

The tested APK is the debug build of `3c04d3b4f1471e925116214712e848100a14cfc2`. The old checkpoint dataset was created in the app after recovery by adding and editing a fictional sentinel and removing the already-returned fictional book. It had three books, four history rows and one managed cover. The archive retained its original three book IDs and six history rows. Snapshots compared every application table, including IDs, encoded loans, dates and preferences.

Each location in `lib/services/library_backup.dart` was reached as a resolved Dart VM breakpoint. With the isolate paused, the harness recorded the journal state and called `adb shell am force-stop com.kamilloo.mylibrary`. After starting the app again it verified a new PID, an interactive library, SQLite integrity, foreign keys, the expected dataset and the referenced managed cover. Breakpoints were attached to the standard debug build. The app contains no fault-injection hook.

| Breakpoint | Observed before force-stop | Result after launch |
| --- | --- | --- |
| Line 180, before the replacement transaction | Debugger paused before entering the SQLite transaction. No cover journal existed. | Exact old rows and cover references survived. No mixed records. |
| Line 215, after cover staging and uncommitted database writes | The journal named two existing files, one old cover and one newly staged cover. | SQLite rolled back to the exact old rows and cover references. Startup discarded the abandoned cover. |
| Line 230, after commit and before cover cleanup | SQLite already matched the archive, including the new cover digest. Both journal candidates still existed. | The committed library survived, the old sentinel was absent and only the referenced cover remained. |

Each restart left no live cover journal. SQLite integrity was `ok`, the foreign-key check returned zero rows, and Android registered exactly one return alarm for ID 1.

## Commands and evidence

Use `emulator -list-avds` and `emulator -accel-check`, then launch the disposable AVD with `-accel on -no-snapshot -no-window -no-audio -gpu swiftshader_indirect`. Use `adb devices -l`, both `getprop` checks above, `flutter build apk --debug`, `adb -s emulator-5580 install`, and `adb -s emulator-5580 shell am start -n com.kamilloo.mylibrary/.MainActivity`. Restrict all uninstall, force-stop and `run-as` commands to the disposable emulator. Use `adb logcat` for installation and startup checks, `unzip -t` and SHA-256 for the selected archive, read-only `sqlite3` checks on copies, and `adb shell dumpsys alarm` for actual system scheduling.

Screenshots are native emulator captures. The valid backup, damaged copies, private SQLite snapshots and full emulator logs are outside the repository.

- [Android version](android-version.png)
- [Help buttons](help-buttons.png)
- [Backup screen](backup-screen.png)
- [Native save picker](save-picker.png)
- [Export success](export-success.png)
- [Restore confirmation](restore-confirmation.png)
- [Restore success](restore-success.png)
- [Restored managed cover](restored-cover.png)
- [Restored lending records](restored-lending.png)
