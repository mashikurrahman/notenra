# Notenra — iOS bring-up (on a Mac)

This is the **Flutter** app (cross-platform). The iOS project lives in `ios/`.
Everything below runs on **macOS only** (Xcode + iOS Simulator are macOS-only).

App bundle id: `com.notenra.notenra` · Display name: **Notenra**

---

## 1. Prerequisites (install on the Mac)
- **Xcode** (from the App Store) + command-line tools: `xcode-select --install`
- **CocoaPods**: `sudo gem install cocoapods`
- **Flutter SDK**: https://docs.flutter.dev/get-started/install/macos
- Verify: `flutter doctor` (all green for iOS)

## 2. Run on the iOS Simulator (fastest, no Apple account)
```bash
cd notenra
flutter pub get            # plugins resolve via SPM — no `pod install` needed
open -a Simulator          # boots an iOS Simulator
flutter run                # builds + installs on the simulator
```

## 3. Run on a real iPhone (needs signing)
```bash
open ios/Runner.xcworkspace   # open the WORKSPACE, not the .xcodeproj
```
In Xcode → select the **Runner** target → **Signing & Capabilities** →
- set your **Team** (a free Apple ID gives 7-day device installs; the $99/yr
  Apple Developer Program is needed for TestFlight / App Store).
- Xcode auto-manages the provisioning profile.
Then plug in the iPhone and `flutter run` (or press ▶ in Xcode).

## 4. Capabilities already configured in this repo (verify they survive signing)
- `Info.plist`: `NSMicrophoneUsageDescription`, `NSFaceIDUsageDescription`,
  App Transport Security (no cleartext), **`UIBackgroundModes: audio`**, and
  `ITSAppUsesNonExemptEncryption = false` (export compliance).
- `SceneDelegate.swift`: privacy **blur overlay** when backgrounded (iOS has no
  `FLAG_SECURE`).
- iOS deployment target: **13.0** (`ios/Runner.xcodeproj/project.pbxproj`).
- Plugins with iOS platform code: `record`, `flutter_foreground_task`,
  `just_audio`, `local_auth`, `flutter_secure_storage`, `sqflite_sqlcipher`,
  `connectivity_plus`, `path_provider`, `wakelock_plus`, `encrypt`,
  `flutter_local_notifications`.
- **Dependency resolution is Swift Package Manager**, not CocoaPods — there is
  no committed `Podfile`. `flutter build` generates one only if some future
  plugin lacks SPM support.

> There is **no** home-screen widget on either platform: `home_widget` is not a
> dependency and no `ios/NotenraWidget/` target exists. (An earlier draft of
> this document described one.)

## 5. What the Simulator CAN vs CANNOT test
- ✅ UI, navigation, layout, most logic, login/vault flow.
- ❌ **Real microphone / recording**, **background audio**, **Face ID hardware**,
  push — these need a **real iPhone** (TestFlight or a wired device). Don't sign
  off the recording engine on the simulator alone.

## 6. Production build (no demo logins)
```bash
flutter build ipa --release --dart-define=DEMO_ACCOUNTS=false
```
Omitting the flag seeds the local encrypted DB with built-in demo logins
(`dr.smith@notenra.health` / `admin`) and fake patient rows — fine for a
simulator or Appetize preview, **never** for anything that reaches real users.
The `ios-release` workflow in `codemagic.yaml` passes it automatically; the
Appetize simulator workflow deliberately does not, so previewers can explore
demo mode without a live server.

Backend mode is separate: builds default to the **live** server, and
`--dart-define=LIVE_BY_DEFAULT=false` produces a demo-data build.

## 7. Common fixes
- Stale build: `flutter clean && flutter pub get`
- Pod errors (only if a `Podfile` has been generated):
  `cd ios && pod repo update && pod install`
- Min iOS: this project targets a modern iOS; bump `ios/Podfile` `platform :ios`
  if a pod requires a higher floor (the error will name it).
