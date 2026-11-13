# Android V1 release preparation

Current product scope and implementation status are owned by the
[canonical Android V1 specification](MyLibrary_Version_1_Updated_Specification.txt).
The validation record below is the **Task 12 / PR #13 historical release-preparation
snapshot** (194 tests), not a fresh run against today's source. Later merged QR,
SMS and tutorial changes require a new release candidate and device QA. Active
schema is v5; later test-count snapshots are listed in the canonical specification.
Original build/signature/checksum evidence and dates are preserved.

## Task 20: offline SMS messaging

SQLite schema v5 adds separate local message/decision and opt-in contact tables;
existing books/history/reminders and Task 19 payloads are preserved. No restricted
SMS or contacts permissions, backend, Firebase or advertising changes are added.
ACTION_SENDTO only opens a composer; delivery and identity are unverified.
See [protocol, privacy and physical-device gates](offline_loan_messaging.md).
Physical SMS application checks remain pending; host tests do not prove delivery.



## Status and release gates

This prepares **Moja Biblioteka** for Android release review; it does not authorize
publication. Physical-device install/upgrade/delivery QA is pending: no Android
device was connected. See [the execution checklist](android_qa_checklist.md).
Confirming the intended production signing identity and Play Console work require
the developer. Existing private local signing configuration is used for host
build verification. No signing key was generated, no credentials were
printed/committed, and no Play Console was accessed.

See the validation record below for the distinction between builds, signing
verification and actual release readiness. A successful debug build is not a
production artifact. Do not distribute a release candidate until its certificate,
signed APK/AAB, installed upgrade path and device QA have been verified.

## Identity, versions and toolchain

| Setting | Current value |
| --- | --- |
| Display name | Moja Biblioteka |
| Application ID / namespace | com.kamilloo.mylibrary |
| Launcher | .MainActivity, exported for launcher only |
| Version name/code | 1.0.0 / 8 from pubspec.yaml |
| Minimum Android | API 24 — Android 7.0 |
| Target Android | API 36 — Android 16 (Flutter 3.47.5 default) |
| Compile SDK | 37.0, minorApiLevel = 0 |
| Flutter / Dart used in CI | 3.47.5 / 3.13.4 |
| Android Gradle Plugin | 9.1.1 |
| Gradle wrapper | 9.3.1 |
| Kotlin plugin declaration | 2.4.0; app uses AGP built-in Kotlin |
| Java/Kotlin bytecode | 17 |
| CI build JDK | Temurin 17 |
| Local build JDK | Android Studio JBR 25.0.4; shell java is not on PATH |
| NDK | Flutter default 28.2.13676358 |
| Desugaring | desugar_jdk_libs 2.1.4 |
| Android build tools observed locally | 36.0.0 |

Use the CI Flutter version and committed pubspec.lock. The permissive Dart SDK
range in pubspec.yaml is not evidence that the current lockfile works on older
Flutter releases. Install SDK platform `platforms;android-37.0`, SDK build tools,
platform-tools, command-line tools and the required NDK; accept SDK licenses.
Use `flutter doctor -v` to confirm Flutter's selected JDK. For direct Gradle or
SDK Java tools, set JAVA_HOME to a compatible JDK (17 recommended).

No maximum SDK is imposed. API 24+ is the configured installation range, not a
claim that every Android version/device has been physically tested. No application
ID, version code, database name or schema change was necessary for this task.
Before publishing, select a version code greater than every previously uploaded
build; for example `--build-name=1.0.0 --build-number=<next-unused-code>`.
Do not assume code 8 is unused in a console this task has not accessed.

Launcher resources retain the existing bookshelf artwork. Android-only icon
generation is reproducible with:

```bash
dart run flutter_launcher_icons -f android_launcher_icons.yaml
```

Legacy density PNGs and API 26+ adaptive foreground/background resources must be
included; round/squircle/themed-launcher appearance remains a device QA check.
No monochrome/themed icon is claimed.

## Secure signing

Release configuration reads an ignored **android/key.properties** or these
environment variables, with environment values taking precedence:

| Property | Environment variable |
| --- | --- |
| storeFile | MY_LIBRARY_STORE_FILE |
| storePassword | MY_LIBRARY_STORE_PASSWORD |
| keyAlias | MY_LIBRARY_KEY_ALIAS |
| keyPassword | MY_LIBRARY_KEY_PASSWORD |

Copy the placeholder-only `android/key.properties.example` into a private local
configuration. Use an absolute keystore path; relative paths resolve against
`android/app`. On Windows use forward slashes or properly escaped backslashes.
Do not put real values into the example or command-line arguments. Supply
environment values through a secure local secret manager/CI secret environment;
never print them, enable shell tracing, or upload Gradle caches containing secrets.
Do not put secrets in pull-request workflows or workflows from untrusted forks.

Key properties, keystores (.jks/.keystore/.p12/.pfx), local environment files and
android/keystores are ignored. Ignoring files does not untrack an already committed
secret: if one is ever committed, rotate it and follow incident remediation.
Keep keys outside the repository and restrict filesystem permissions.

Release pre-build validation checks for all four values and an existing keystore
file. Missing credentials fail with an explicit message pointing here. There is
**no debug-signing fallback** and no automatic key creation. Debug builds do not
require release credentials. Wrong alias/password/certificate still requires
actual signing verification; a configuration check alone cannot prove correctness.

The developer, not this automation, may generate a new upload key after deciding
the signing policy, using an interactive command such as:

```bash
keytool -genkeypair -v -storetype JKS -keystore /private/path/upload-keystore.jks -alias upload -keyalg RSA -keysize 3072 -validity 10000
```

Let keytool prompt for passwords. Do not run this for an app that already has a
required signing identity. Maintain encrypted, access-controlled offline backups
of the keystore and recovery information; test recovery privately. Losing a
self-managed app-signing key may prevent future upgrades. With Play App Signing,
Google holds the **app signing key** used for delivered APKs; the developer holds
an **upload key** used to authenticate AAB uploads. Upload-key reset is different
from app-signing-key recovery/rotation. A locally upload-key-signed APK may not
upgrade a Play-installed APK signed by a different app-signing key.
[Android signing guide](https://developer.android.com/studio/publish/app-signing).

## Builds and artifact verification

Run from repository root:

```bash
flutter clean
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
flutter build apk --release
flutter build appbundle --release
git diff --check
```

Expected output locations:

| Artifact | Path | Purpose |
| --- | --- | --- |
| Debug APK | build/app/outputs/flutter-apk/app-debug.apk | Development only, debug certificate |
| Release APK | build/app/outputs/flutter-apk/app-release.apk | Only distributable after release certificate verification |
| Release AAB | build/app/outputs/bundle/release/app-release.aab | Signed upload to Play internal testing, not directly installable |

Without credentials, release commands must fail; do not bypass validation or
rename a debug/unsigned APK to satisfy a release gate. Failed builds may leave
older artifacts on disk; verify modification time, checksum and source commit,
not just filename existence.

With securely supplied credentials, use SDK tools (substitute SDK/tool versions):

```bash
apkanalyzer apk summary build/app/outputs/flutter-apk/app-release.apk
apkanalyzer manifest min-sdk build/app/outputs/flutter-apk/app-release.apk
apkanalyzer manifest target-sdk build/app/outputs/flutter-apk/app-release.apk
apkanalyzer manifest debuggable build/app/outputs/flutter-apk/app-release.apk
apkanalyzer manifest permissions build/app/outputs/flutter-apk/app-release.apk
apkanalyzer manifest print build/app/outputs/flutter-apk/app-release.apk
apksigner verify --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk
zipalign -c -P 16 4 build/app/outputs/flutter-apk/app-release.apk
jarsigner -verify -verbose -certs build/app/outputs/bundle/release/app-release.aab
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
sha256sum build/app/outputs/flutter-apk/app-release.apk build/app/outputs/bundle/release/app-release.aab
```

Confirm ID, code/name, SDKs, release debuggable=false, no unwanted permissions,
expected certificate fingerprint (not Android Debug), and successful signature
verification. AAB uses JAR signing, not apksigner. Self-signed certificate warnings
are expected for Android keys, but unsigned entries, verification failures or an
unexpected fingerprint block release. Retain expected fingerprints privately in
the release record.

Use official bundletool to validate the AAB and generate/install device APKs with
the appropriate secure signing configuration, then test through Play internal
testing. Avoid putting passwords into shell history. Verify native ELF LOAD
segment alignment as well as ZIP alignment; `zipalign -P 16` alone does not prove
all native libraries support 16 KB pages. Test a 16 KB runtime.
[Android native-page guidance](https://developer.android.com/guide/practices/page-sizes).

## Permissions and components

| Permission/component | Reason and behavior |
| --- | --- |
| CAMERA | User-initiated scanner and camera-cover operation; runtime grant/denial handled by plugins/UI |
| INTERNET | HTTPS Open Library search/ISBN metadata and remote cover image retrieval; planned advertising SDK network requirements must be audited on integration |
| com.google.android.gms.permission.AD_ID | Prepared for planned Google Play services Advertising ID use; normal permission, not a runtime prompt or consent grant |
| POST_NOTIFICATIONS | Android 13+ permission only after explicit eligible reminder opt-in |
| RECEIVE_BOOT_COMPLETED | Restore plugin schedules after reboot/package update |
| VIBRATE (merged plugin permission) | Notification vibration, normal permission without a runtime prompt |
| ACCESS_NETWORK_STATE (merged SDK permission) | Existing ML Kit/transport connectivity checks, normal permission |
| DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION (app-scoped) | AndroidX signature-protected receiver compatibility; not a public data API |
| MainActivity exported=true | Required launcher activity; no app deep-link or data-modifying intent API |
| ScheduledNotificationReceiver and ScheduledNotificationBootReceiver exported=false | Private plugin scheduling/recovery components |
| UCropActivity exported=false | Private crop activity |
| ImagePickerFileProvider | Packaged exported=false, grants individual temporary content-URI access |
| CmUCropActivity | Plugin crop activity, no intent filters; defaults to non-exported |
| ProfileInstallReceiver exported=true | AndroidX component protected by android.permission.DUMP; not an unprotected public receiver |
| ML Kit/Google transport and AndroidX startup components | Packaged services/providers/receivers are non-exported (or disabled), except the permission-protected profile receiver |

Advertisements are planned for Moja Biblioteka. A single standard **AD_ID**
declaration is restored for intended advertising SDK use; this correction adds
no advertising SDK, ID-reading code or ad placements. No contacts/location, exact-alarm or
foreground-service feature is introduced. System Photo Picker (with supported fallback) is enabled
by CoverPicker; no READ/WRITE_EXTERNAL_STORAGE or READ_MEDIA_IMAGES permission
is required. A camera is optional hardware, so manual entry remains available
without one. App traffic disallows cleartext HTTP. Legacy user-supplied HTTP
cover references may therefore show a placeholder; use HTTPS or a local cover.

Permissions must not be prompted for during launch/automatic reconciliation.
The corrected release APK and AAB were inspected with SDK tools: each contains
exactly one AD_ID declaration alongside the existing seven permissions (eight total). Broad storage, location, exact-alarm
and foreground-service permissions remain absent. Recheck the final merged
release manifest after advertising SDK integration; source inspection alone is
insufficient. AndroidX may add its signature-protected dynamic receiver
permission or platform components; distinguish those from public app APIs.
Existing debug/profile INTERNET manifests support Flutter tooling; release
debuggability must be checked in the release artifact. Transitive ML Kit/Google
transport components support the scanner's SDK diagnostics; they are existing
dependencies, not a new application analytics feature.

## Privacy, storage and backup policy

Books, descriptions/legacy directory values, borrowers, dates, history and reminder
preferences stay in app-private SQLite. The database is **not application-level
encrypted**; Android sandbox/device encryption protects normal access, not an
unlocked compromised/rooted device. No backend, account, remote library database,
application telemetry or push token is added. The existing scanner SDK has its
own diagnostic behavior, described below.

Open Library receives only user-requested ISBN/title/author queries and normal
HTTP metadata such as IP/User-Agent. Cover images are fetched from their stored
URLs when rendered; remote image servers also see these requests. Borrower names
and lending history are not inputs to the metadata service. The external provider
has its own logging/policy; do not claim zero external data transmission or
automatically answer the Play Data safety form without reviewing those flows.

The scanner uses existing Google ML Kit dependencies. Google documents diagnostic
collection including device/app information, installation identifiers, performance
metrics and SDK configuration/event information. Account for this when preparing
the privacy policy/Data safety form and verify behavior on device; do not claim
that a bundled on-device barcode model makes the entire SDK network-silent.
No borrower/history object is supplied to the scanner or metadata SDK.
[ML Kit Android data disclosure](https://developers.google.com/ml-kit/android-data-disclosure).

Exception/stack logging for reminder sync and cover cleanup is now debug-only,
matching save/edit logging. SQLite exceptions can contain row/path data and must
not be emitted to release logcat. No hardcoded production credentials or private
keys were found in the inspected application source. This is a bounded source
audit, not a historical Git secret-scanner certification.

**V1 deliberately disables Android cloud Auto Backup and device-to-device data
transfer.** `allowBackup=false` and legacy `fullBackupContent=false` disable
ordinary backup; Android 12+ extraction rules explicitly exclude root/file/
database/sharedpref/external for both transports because some manufacturers
treat allowBackup differently for transfers. This prevents borrower-data upload
and partial database/cover/native-schedule restoration.
[Android backup behavior](https://developer.android.com/identity/data/autobackup).

Updates installed over the same app with a compatible certificate preserve private
data in place; disabling backup does not delete it. **Uninstall, clear-data, lost
devices and phone replacement have no V1 recovery/export mechanism.** Disclose this
before release. This policy does not retroactively erase any backup an older app
version may already have made; any future migration/import/backup feature requires
a separate reviewed design and tests. OEM transfer behavior still needs device QA.

## SQLite, covers and reminders

Production path stays `getDatabasesPath()/my_library.db`; active schema is **5**.
Additive upgrades support **1/2/3/4→5** and current-v5 reopen: v2 adds the history
index, v3 reminders, v4 loan transfers/borrower records, v5 messages/contacts.
The original Task 11/12 evidence below concerned v3; current source and migration
suites extend preservation checks to v5. Preserve complete books/history, cover
references, opt-in/IDs, v4 borrower rows and v5 messages/contacts. Installed-device
upgrades remain pending. Empty reads never seed demo books; no destructive
migration is added. See the [historical SQLite audit](sqlite_regression_audit.md),
[QR protocol](offline-loan-protocol.md), [message migration](offline_loan_messaging.md)
and [canonical schema](MyLibrary_Version_1_Updated_Specification.txt).

Managed covers are copied into application-support `covers/<uuid>.jpg` and stored
as relative references. Cache/picker files are not durable storage. Existing
ownership/reference checks prevent unsafe cleanup of saved/shared/user-owned
images. retrieveLostData recovery is wired on app startup; lost unsaved cropper
drafts are not a promise of persisted book data. Legacy absolute paths may fail
after path changes; missing images have placeholders. A process interruption can
leave orphan temporary/copied files; no risky broad cleanup is introduced.

Reminders use channel **book_returns / Terminy zwrotu**, private lock-screen
visibility and inexactAllowWhileIdle at local 09:00. Opt-in defaults off, IDs remain
stable, nearest 60 eligible dates are scheduled, and startup/resume reconciliation
does not prompt. Loan/date updates commit independently of OS scheduling failures.
Reboot/update receivers recover plugin schedules. Timezone changes are reconciled
on next app resume; while closed, the previous timezone schedule can remain.
Doze, force-stop, channel/permission blocks and OEM battery policies can delay or
prevent delivery. No exact 09:00 guarantee is made.
See [reminder limits](return_reminders.md) and device cases N01–N09.

## Advertising readiness — integration pending

The developer reports that advertising plans have been declared in Google Play
Console. This audit does not access or independently verify that Console state.

**Contains ads** and the **Advertising ID declaration** are separate requirements:
the former describes ad presence in the product/listing; the latter describes
whether the shipped app or its SDKs use Advertising ID and for which purposes.
Neither the permission nor a Contains ads answer proves actual ID access, correct
consent handling, or completed Data safety disclosures.
[Play app-content declarations](https://support.google.com/googleplay/android-developer/answer/9859455),
[Advertising ID guidance](https://support.google.com/googleplay/android-developer/answer/6048248).

For apps targeting API 33+, Google Play services Advertising ID access requires
AD_ID. The app supplies one plain uses-permission declaration now, with no
tools:node removal/replacement rule. SDK manifests declaring the same permission
merge by android:name into one effective entry; do not add competing declarations
or variant-specific overrides. Once the intended SDK/version is selected, verify
its actual requirements and the merged release APK/AAB. A library-supplied entry
can be the sole source after verifying all shipped variants; do not remove
advertising support on an assumption that ads are unwanted.
[Android Advertising ID permission and merging](https://developer.android.com/about/versions/13/behavior-changes-13#advertising-id).

Before publishing an advertising-enabled version, verify the intended SDK and
any mediation adapters, initialization and actual ad integration in a separately
authorized task. Review SDK data disclosures, applicable consent/age/region
handling, ID deletion/opt-out behavior, privacy policy and Google Play Data safety
answers against the actual build and data flows. Do not pass borrower names,
library records or lending history as ad-targeting parameters. Test consent and
ad behavior on devices; every such case remains pending. This permission-only
correction does not establish advertising readiness or authorize publication.

## Google Play prerequisites — not executed

Reviewed authoritative requirements on 2026-11-10; recheck at actual submission:

- Confirm developer identity/verification, application ID ownership, listing name,
  descriptions, contact details, supported devices and countries.
- Current mobile new-app/update policy requires API **36+** from August 31, 2026;
  configured target 36 meets that number, but does not prove full policy compliance.
  [Target API requirement](https://developer.android.com/google/play/requirements/target-sdk).
- Enroll/configure Play App Signing and securely manage upload key; verify intended
  app-signing fingerprint and upgrade compatibility. Upload a verified signed AAB.
- Supply store icon, phone screenshots and any tablet assets required by selected
  device support. Check adaptive masks and actual accessibility on devices.
- Publish a privacy policy consistent with local borrower storage, no cloud backup,
  Open Library queries and remote cover requests. Complete Data safety from actual
  app/SDK behavior, including any applicable ephemeral data transmission.
  [Data safety guidance](https://support.google.com/googleplay/android-developer/answer/10787469).
- Verify the separate Contains ads and Advertising ID declarations against the
  advertising-enabled release and SDK behavior; advertising is planned. Complete
  content rating, target audience, app access (no account), permissions
  declarations and other applicable content forms.
- Check native 16 KB support, current SDK/policy deadlines and pre-launch reports.
- Run internal testing and installed-upgrade QA; satisfy any account-specific
  testing prerequisites before production access. Decide version code and rollout,
  monitor user-visible failures without adding analytics in this task.
- Preserve signing/rollback recovery procedures: never reinstall/clear data to
  conceal an incompatible certificate, and do not assume version downgrade is safe.

No Play Console login, upload, internal-track release or production rollout was
performed. Public release is a separate explicit authorization and QA gate.

## Validation record

- Host: Ubuntu 22.04.5; Flutter 3.47.5 / Dart 3.13.4.
- Clean dependency resolution, formatting, analysis and **194 tests**: passed.
- Debug APK: builds successfully; development artifact only.
- Release APK: built with existing private signing configuration; apksigner
  verification passed (v2), release debuggable=false. No Android Debug certificate.
- Release AAB: built; jarsigner reports "jar verified"; keytool shows the same
  certificate as the APK. Google bundletool 1.18.3 validation passed.
- JDK 25 jarsigner also warned about self-signing, no timestamp, and ZIP entry
  order causing JarInputStream/JarFile differences. Do not hide these warnings:
  repeat signature review with the CI-recommended JDK 17 and validate through
  Play internal testing before public release. Bundletool validation does not
  itself prove the intended signing identity or Play acceptance.
- APK zipalign check with -P 16 passed. Native ELF alignment and a 16 KB runtime
  remain pending; ZIP alignment alone is insufficient.
- Packaged manifest: API 24/36, com.kamilloo.mylibrary, 1.0.0+8;
  corrected APK/AAB manifests verified with eight permissions including one AD_ID entry,
  backup/cleartext disabled. No advertising SDK is installed by this correction.
- Existing signing material was neither generated nor read into audit output.
  Missing-credentials assembleRelease and bundleRelease rejection passed locally
  with all four signing variables explicitly empty, and is also checked in CI.
- Historical pre-advertising-correction artifact SHA-256 (these do not identify
  the corrected manifest; regenerate for a new release candidate):
  APK: `18cc021937c30220f139dbf8b9ce1ddf6b25ca28a0d7d20f461f4facf480234a`;
  AAB: `0114a917bcf7e9999dc1d6f0843572c81c5b00b67f6e0820c6e8baa1c33f7160`.
  Future rebuilds may differ; regenerate checksums and record the source commit.
- Physical-device execution: none; every device scenario remains Pending.
- CI quality-checks and android-build: final commit results are recorded in the PR.
