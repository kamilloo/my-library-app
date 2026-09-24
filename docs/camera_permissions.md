# Camera permissions

Apply these changes after running:

```bash
flutter create --platforms=android,ios .
```

## Android

In `android/app/src/main/AndroidManifest.xml`, add this line directly inside the
root `<manifest>` element and before `<application>`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

The beginning of the file should resemble:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.CAMERA" />
    <application
        android:label="my_library"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
```

## iOS

In `ios/Runner/Info.plist`, add this pair inside the top-level `<dict>`:

```xml
<key>NSCameraUsageDescription</key>
<string>Scan book barcodes to add books to your library.</string>
```

Then rebuild the application rather than relying on hot reload:

```bash
flutter clean
flutter pub get
flutter run
```
