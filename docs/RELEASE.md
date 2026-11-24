# NoteShelf release guide

The repo does not contain the generated `android/` and `windows/` runner folders.
`tool/setup_platforms.sh` (and CI) generate them with `flutter create` and apply the SAF plugin.

## Build locally
Android APK (Flutter + JDK 17 + Android SDK):
```
./tool/setup_platforms.sh
flutter pub get
flutter build apk --release      # build/app/outputs/flutter-apk/app-release.apk
```
Windows (on Windows with Visual Studio "Desktop development with C++"):
```
flutter create --platforms=windows --project-name booknotes --org com.booknotes .
flutter pub get
flutter build windows --release  # build/windows/x64/runner/Release/ (ship the WHOLE folder)
```
Checks: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`.

## Android signing
Create a keystore once (`keytool -genkeypair -v -keystore release.jks -alias noteshelf -keyalg RSA -keysize 2048 -validity 10000`) and keep it private. Add GitHub repository secrets:
`ANDROID_KEYSTORE_BASE64` (`base64 -w0 release.jks`), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
Locally, export the same variables before running `tool/setup_platforms.sh`. Without them the APK is signed with the debug key and must not be distributed.

## GitHub Release (manual)
CI uploads `noteshelf-android-apk` and `noteshelf-windows` as workflow artifacts. Download them from the run page, then create a release on GitHub and attach the APK and the Windows ZIP. Nothing publishes automatically.

## Limitations
- Windows data lives in `Documents\BookNotes`; Android internal library is app-private.
- Android SAF folders need the persisted permission; revoked folders show a reconnect message.
- Folder moves are not supported over SAF (internal books use the dart:io backend).
