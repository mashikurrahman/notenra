# NOTENRA — STORE SUBMISSION & DEPLOYMENT GUIDE (PLAY STORE & APP STORE)

This guide contains all necessary steps, artifacts, metadata, and instructions to publish Notenra to the **Google Play Store** and **Apple App Store**.

---

## 1. Google Play Store Submission (Android)

### Ready-to-Upload Artifacts
The release-signed Android App Bundle (AAB) is generated and located at:
* **Play Store App Bundle (AAB):** [`d:\notenra\release_builds\notenra-v1.0.2-playstore.aab`](file:///d:/notenra/release_builds/notenra-v1.0.2-playstore.aab) *(or `d:\notenra\build\app\outputs\bundle\release\app-release.aab`)*
* **Direct Installable APK:** [`d:\notenra\release_builds\notenra-v1.0.2-release.apk`](file:///d:/notenra/release_builds/notenra-v1.0.2-release.apk)

### App Specifications
* **Package Name:** `com.notenra.notenra`
* **Version Name:** `1.0.2`
* **Version Code:** `3`
* **Minimum Android SDK:** `23` (Android 6.0 Marshmallow)
* **Target Android SDK:** `34` (Android 14)
* **Signing Key:** Signed with `upload-keystore.jks` (`upload` alias).

### Play Console Upload Steps
1. Log in to the [Google Play Console](https://play.google.com/console).
2. Select your Notenra application (or click **Create App**).
3. Navigate to **Production** (or **Closed testing / Internal testing**) > **Create new release**.
4. Drag and drop `notenra-v1.0.2-playstore.aab`.
5. Enter Release notes:
   ```
   • Ambient AI SOAP note generation with ICD-10 & CPT medical coding
   • Multi-recording audio aggregation for single patient encounters
   • Offline sync queue with AES-GCM encrypted audio storage
   • Performance, stability, and HIPAA technical safeguard enhancements
   ```
6. **Data Safety Declarations in Play Console:**
   * **Audio recordings:** Collected & encrypted in transit / at rest for app functionality (Clinical transcription).
   * **Personal info (Name, Email):** Collected for account management & authentication.
   * **Data Encryption:** All data encrypted in transit (HTTPS / TLS) and at rest.
   * **Data Deletion:** Clinicians can request deletion or auto-purge local recordings.

---

## 2. Apple App Store Submission (iOS)

### iOS Configuration Summary
The iOS project is configured with all required permissions and declarations in [`ios/Runner/Info.plist`](file:///d:/notenra/ios/Runner/Info.plist):
* **Bundle Identifier:** `com.notenra.notenra` (or your configured team bundle ID)
* **Version / Build:** `1.0.2` / `3`
* **Export Compliance (`ITSAppUsesNonExemptEncryption`):** Set to `<false/>` (Uses standard exempt HTTPS & AES data protection; avoids export compliance review pauses).
* **Privacy Permissions Configured:**
  * `NSMicrophoneUsageDescription`: *"Notenra records clinical consultations so they can be transcribed into your notes."*
  * `NSFaceIDUsageDescription`: *"Face ID unlocks the encrypted vault that protects patient health information."*
  * `UIBackgroundModes`: `audio` (allows background consultation recording).

### Building the iOS Release Archive
*(Apple requires macOS + Xcode to compile the final `.ipa` or Xcode Archive)*

#### Option A: Building on a Mac with Xcode
1. Open the project in Terminal on a Mac:
   ```bash
   cd notenra
   flutter pub get
   cd ios && pod install && cd ..
   flutter build ipa --release
   ```
2. Open `ios/Runner.xcworkspace` in Xcode.
3. Select **Product > Archive**.
4. In the Organizer window, click **Distribute App** > **App Store Connect** > **Upload**.

#### Option B: Automated Build via GitHub Actions / CI
If building via GitHub Actions (`.github/workflows/ios_release.yml`), run:
```yaml
name: Build iOS Release
on: [workflow_dispatch]
jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x'
      - run: flutter pub get
      - run: flutter build ipa --release --export-options-plist=ios/ExportOptions.plist
```

---

## 3. Pre-Launch Checklist

- [x] All 46 automated unit and integration tests passing (`flutter test`).
- [x] Static code analysis clean with 0 warnings (`flutter analyze`).
- [x] Medical coding (ICD-10-CM & CPT) verified.
- [x] Offline outbox synchronization tested.
- [x] AES-GCM AudioVault encryption at rest verified.
- [x] Multi-recording deduplication verified (1 card per patient encounter).
- [x] Release App Bundle generated (`notenra-v1.0.2-playstore.aab`).
