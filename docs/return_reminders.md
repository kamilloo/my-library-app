# Local return reminders

Current Android V1 scope: [canonical specification](MyLibrary_Version_1_Updated_Specification.txt).
Active SQLite schema is **v5**; the reminder table was introduced in v3 and is
preserved by later migrations. iOS setup/limits below are retained as technical
reference for a deferred platform, not a current supported release or device-QA
claim. Android physical delivery and reboot verification remain pending.

## Behavior

On a borrowed book's Details screen, choose **Zmień termin zwrotu**, then enable
**Przypomnij o zwrocie**. Every new loan starts with reminders off. A nonempty
borrower and a return date whose 09:00 is still in the future are required.
No account, server, push token, or remote notification service is used.

The app uses flutter_local_notifications 23, flutter_timezone, and the timezone
database. It schedules a one-shot notification at 09:00 in the device's IANA
timezone on the calendar return date. DST is taken into account. A past time is
skipped rather than firing immediately. The notification includes the book title
but not the borrower. Android lock-screen visibility is private; iOS previews
follow the user's system settings.

The reminder table, introduced in SQLite schema version 3 and retained in current
schema version 5, stores per-book opt-in and an AUTOINCREMENT notification ID.
The plugin persists native schedules. The same ID is reused, so repeated
requests and restarts do not create duplicates. Returning, giving away, deleting,
or explicitly disabling cancels the notification. Changing/removing a return date
reschedules/cancels it. A new loan requires a new opt-in.

Startup and app resume reconcile saved intent with current loans, permissions,
and device timezone, without permission prompts. The native pending-request payload
stores a versioned schedule fingerprint (book ID, title, instant, timezone).
Unchanged pending reminders are left untouched, including after app restart;
older book-ID-only payloads are replaced once using the same notification ID.
Changed schedules replace their own ID without a preceding cancellation.
Each scheduling/cancellation failure is isolated; independent books are still
attempted and saved opt-in intent remains available for retry. If native inventory
cannot be read, reconciliation stops before changing schedules. Failed cancellations
and uncertain scheduling outcomes conservatively reserve queue slots until native
inventory is read again; this can temporarily defer a nearer reminder, but prevents
exceeding the 60-request policy. If permissions are revoked,
pending reminders are canceled on the next reconciliation. OS failures never
roll back loan writes; saved intent is retried on the next resume. Cancellation
failures can therefore leave an old OS notification until synchronization succeeds.
Rows for deleted books retain only the old book UUID, disabled flag, and ID so
cancellation can be retried after a crash; no borrower or title is stored there.

## Build setup

Dependencies are locked in pubspec.lock. Use the CI Flutter version (3.47.5).
Android uses compile SDK 37.0 (minorApiLevel = 0), AGP 9.1.1, Java 17, and
desugar_jdk_libs 2.1.4 as required by the notification package. Install SDK
platforms;android-37.0 with SDK Manager if Gradle cannot download it. Target SDK
behavior remains controlled by Flutter. Android manifest declares POST_NOTIFICATIONS,
RECEIVE_BOOT_COMPLETED, and non-exported scheduled/boot receivers. No exact alarm,
foreground service, or remote push permission/service is added. The notification
icon is a dedicated white drawable.

For iOS, run flutter pub get and install pods on macOS before building with Xcode.
No remote push entitlement or background mode is needed for these local reminders.

## Permissions and platform limits

- Android 13+: POST_NOTIFICATIONS is requested only after the user enables a
  valid reminder. A rationale is shown after a prior denial when Android requests
  one. **Ustawienia powiadomień** opens system settings after denial or channel
  blocking. Android 8+ uses the **Terminy zwrotu** channel.
- Android schedules use inexactAllowWhileIdle. No exact-alarm special access is
  requested. Delivery can be delayed by Doze, battery saving, manufacturer
  restrictions, notification blocking, or force-stop. Boot/package-replacement
  receivers restore plugin schedules after reboot/update. Force-stopped apps
  generally need to be opened again. This is a convenience reminder, not an alarm.
- iOS authorization is deferred until explicit opt-in; startup never prompts.
  AppDelegate sets the notification-center delegate for foreground presentation.
  Focus, notification summaries, and system preview settings affect presentation.
- iOS has a 64 pending local-notification limit. The app schedules only the nearest
  60 eligible return dates on both platforms, leaving headroom. Additional enabled
  dates are deferred until the app is opened/resumed and the queue is refilled.
  Opening the app regularly is necessary when more than 60 reminders are enabled.
- OS schedules survive process termination, but delivery is not guaranteed by the
  app. Reinstalling/clearing app data removes local opt-ins. Timezone changes are
  reconciled on next resume; while the app stays closed the existing native
  schedule retains its previously scheduled timezone.
- Current supported release target is Android. Existing iOS adapter/setup notes
  are retained for the deferred iOS platform; no iOS release validation is claimed.
  No desktop/web scheduling is configured.

Package setup/limits:
https://pub.dev/packages/flutter_local_notifications
Timezone discovery:
https://pub.dev/packages/flutter_timezone

## Physical-device verification (required before release)

Automated tests exercise policy, SQLite persistence, cancellation, replacement,
and denial using a fake notification backend. They do not prove OS delivery.
Perform this checklist on physical Android 13+ and iOS devices. Use a debug-only
clock/scheduling override or set a future calendar return date and wait until
09:00; restore normal device time afterwards. Do not ship a test override.

1. Fresh install: no notification prompt at launch or when saving a loan.
   Create a loan without date, confirm no reminder can be enabled. Add a future
   date and opt in; accept authorization. Verify channel and one pending request
   through native debugging tools / plugin pendingNotificationRequests.
2. Deny authorization. Loan remains saved; Polish denial feedback and settings
   link work. Retry after enabling system permission. Repeat with Android channel
   disabled and iOS alerts disabled. No prompt loop or duplicate request.
3. Confirm delivery in foreground, background, and after process termination
   (not force-stop). Verify Polish title/body, icon, and lock-screen privacy.
4. Change due date, disable reminder, return book, give book away, delete book:
   inspect pending requests after each operation; the previous ID must disappear
   or be replaced. Reborrow a returned book: reminders must start off.
5. Restart the app and reboot Android: verify one pending request per enabled
   book with the same ID. Verify app-update receiver with an installed upgrade.
6. Change timezone and resume. Confirm 09:00 in the new zone. Check dates on both
   sides of a DST transition (e.g. Europe/Warsaw). Past 09:00 must not fire now.
7. Simulate denied/revoked permissions, battery saving/Doze, force-stop, and
   resume. Record observed delays and manufacturer behavior.
8. On iOS, opt in to more than 60 loans and verify only nearest 60 are pending;
   reopen after a date passes to verify queue refill.
9. Upgrade an installation with schema version 1 or 2; verify books/history are
   intact and all pre-existing loans remain opted out.

iOS builds, signing, authorization dialogs, and actual device delivery require
macOS/Xcode and physical devices; they cannot be validated by the Linux test run.
