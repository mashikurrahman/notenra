# NOTENRA MOBILE APP — DEVELOPER ARCHITECTURE & ONBOARDING GUIDE

Welcome to the Notenra Flutter codebase! This comprehensive document is designed so any new or existing engineer can understand the entire architecture, core data flows, security mechanisms, offline synchronization, AI clinical note generation, and test suites immediately.

---

## 1. System Overview & Technology Stack

Notenra is an offline-first ambient AI clinical documentation application built for iOS and Android.

* **Core Framework:** Flutter 3.x / Dart 3.x
* **State Management:** `Provider` (`ChangeNotifier`, `MultiProvider`, `context.watch/read/select`)
* **Local Storage & Database:**
  * `sqflite_sqlcipher` — Full-page AES-256 encrypted SQLite database.
  * `flutter_secure_storage` via `SecureStore` — Hardware-backed KeyStore / Keychain.
* **Audio Capture & Cryptography:**
  * `record` — High-fidelity M4A/AAC consultation capture.
  * `flutter_foreground_task` — Android foreground service to prevent OS kills during capture.
  * `encrypt` / `dart:isolate` — Background isolate AES-256-GCM audio encryption at rest.
* **Networking & HTTP:**
  * `dio` via `ApiClient` — HTTPS client with JWT Bearer auth, CSRF double-submit, and client attribution.
* **Offline Synchronization Engine:**
  * Custom write-ahead outbox (`SyncEngine`) with atomic queueing and exponential backoff retry.

---

## 2. Directory Structure & File Map

```
lib/
├── main.dart                 # App entry point, startup guards, NotenraApp, RootGate, VaultLockScreen
├── app_state.dart            # Global application state (auth, local DB, audio recorder, UI sync)
├── database.dart             # SQLCipher database helper, schema migrations (v1->v4), CRUD queries
├── security.dart             # PBKDF2 password hashing, DB key management, device ID generation
├── secure_store.dart         # Fail-closed wrapper around FlutterSecureStorage with debug fallback
├── audio_vault.dart          # Background Isolate AES-GCM audio encryption (.enc) at rest
├── audit_scrub.dart          # Deterministic MRN and patient name regex redaction
├── recording_foreground.dart # Android foreground service configuration for background recording
├── status_ui.dart            # Standardized visual presentation (colors, labels, icons) for VisitStatus
├── theme.dart                # Notenra design tokens, colors (Nx), typography, and component styling
├── api/
│   ├── api_client.dart       # Dio HTTP wrapper, JWT attachment, CSRF double-submit validation
│   ├── api_config.dart       # Runtime base URL, environment detection, and build defines
│   ├── client_identity.dart  # Client attribution headers (x-notenra-device-id, user-agent)
│   ├── clinical_models.dart  # Core domain models (Visit, ClinicalNote, NoteFeedback, VisitStatus)
│   ├── live_backend.dart     # Production REST API implementation connecting to Notenra servers
│   ├── mock_backend.dart     # In-memory mock backend with AI SOAP & Medical Coding generator
│   └── token_store.dart      # In-memory + secure storage cache for JWT bearer tokens
├── services/
│   ├── clinical_service.dart # Visit state coordinator, single-encounter deduplication, note cache
│   ├── connectivity_service.dart # Network monitoring, offline latch, reconnection callbacks
│   ├── sync_engine.dart      # Write-ahead persistent outbox for mutations (uploads, edits, approvals)
│   └── notification_service.dart # Local notifications for upload status & note readiness
├── screens/
│   ├── login_screen.dart     # Clinician email/password sign-in screen
│   ├── mfa_screen.dart       # SMS / TOTP multi-factor verification
│   ├── home_shell.dart       # Bottom navigation bar (Dashboard, Patients/Schedule, Notes Queue, Profile)
│   ├── today_screen.dart     # Dashboard overview, "Next Up" hero card, review queue badges
│   ├── patient_list_screen.dart # Daily schedule, patient roster, date scroller, search
│   ├── patient_visit_screen.dart# Audio recorder, waveform, AI Note CTA banner, recording list
│   └── note_review_screen.dart  # SOAP note editor, section tabs, Medical Codes chips, approval footer
└── widgets/
    ├── nx.dart               # Reusable UI components (NxCard, StatusPill, NxEmptyState, NxNoteSkeleton)
    ├── notenra_header.dart   # Branded headers with action buttons and breadcrumbs
    └── pressable.dart        # Haptic-enabled interactive touch wrapper
```

---

## 3. Core Architectural Subsystems & Data Flows

### A. Authentication & Biometric Vault
1. **Login Flow:** User authenticates via `LoginScreen` -> `AppState.login()`.
2. **Tokens & Cookies:** `ApiClient` captures JWT from response body or `Set-Cookie` (`__Host-notenra_session`) and saves it in `TokenStore`.
3. **Root Gate:** `RootGate` (`main.dart`) checks if `currentUser` is present. If yes, it requires biometric verification via `local_auth` (`VaultLockScreen`).
4. **Auto-Lock:** Inactivity timer resets on any screen tap (`Listener` in `NotenraApp`).

### B. Consultation Recording & Audio Vault
1. **Capture:** Clinician taps "Record" in `PatientVisitScreen`.
2. **Foreground Service:** `recording_foreground.dart` launches an active notification to prevent Android process kills.
3. **Saving & Encryption:** Stopping capture calls `AppState.stopAndSaveRecording()`:
   - Stores raw audio to temporary file.
   - Spawns background Dart Isolate (`AudioVault.encryptInPlace()`).
   - Encrypts via **AES-256-GCM** using a 256-bit key from KeyStore (`audio_key_v1`).
   - Replaces plaintext file with `.enc` file and deletes the plaintext file.

### C. Single Encounter Deduplication & Visit Reuse
* **Rule:** A patient encounter must have **exactly one visit record** on the backend, even if the doctor records multiple audio clips (e.g. consultation + addendum).
* **Resolution Pipeline (`ClinicalService.submitRecording`):**
  ```
  reuseId = existingVisitId
         ?? _openUnrecordedVisitId(patientId)
         ?? recordedVisitForPatient(patientId)?.id
         ?? latestVisitForPatient(patientId)?.id;
  ```
* If `reuseId` exists, all new audio uploads append to `POST /api/audio/:visitId` on the server instead of spawning new visits (`POST /visits`). This guarantees the web app dashboard displays **exactly 1 patient card**.

### D. Offline Sync Outbox (`SyncEngine`)
1. When offline or online, mutations (`uploadAudio`, `editNote`, `requestChanges`, `approveNote`) are enqueued into `SyncEngine`.
2. `SyncEngine` writes the `SyncOp` to encrypted persistent storage (`sync_outbox`).
3. When network connectivity is restored (`ConnectivityService.onReconnected`), `SyncEngine.flush()` applies operations in FIFO order with up to 8 exponential backoff attempts.

### E. AI SOAP Note Generation & Medical Coding Pipeline
1. **Audio Synthesis:** Once audio is received, the backend or `MockBackend` drafts the clinical note.
2. **SOAP Structure:** Note format is parsed into structured sections:
   - `SUBJECTIVE`
   - `OBJECTIVE`
   - `ASSESSMENT` (with embedded ICD-10 diagnostic mappings)
   - `PLAN`
   - `CODES` (Dedicated Medical Codes & Billing)
3. **Medical Codes Display (`note_review_screen.dart`):**
   - **ICD-10 Diagnosis Codes** (e.g., `I10 - Essential hypertension`).
   - **CPT / E&M Codes** (e.g., `99214 - Moderate complexity visit`).
   - Rendered as interactive code cards with one-tap clipboard copy buttons.
4. **Auto-Polling:** `NoteReviewScreen` automatically polls the backend every 3 seconds while notes are in the drafting/transcribing state.

---

## 4. Database Schema & Migrations

Database is managed by `AppDatabase` (`lib/database.dart`) at version **4**:

* **`users`**: Clinician accounts, usernames, PBKDF2 password hashes, roles.
* **`patients`**: Patient demographics, MRNs, DOB, specialties, emergency contacts.
* **`recordings`**: Audio metadata, encrypted paths (`.enc`), upload status (`pending` / `uploaded`).
* **`audit_logs`**: Compliance audit trail with `synced` flag (0 = local only, 1 = shipped to server).
* **`appointments`**: Scheduled visits, calendar times, visit types.

---

## 5. Development & Testing Commands

* **Run all tests:**
  ```powershell
  & "D:\flutter\bin\flutter.bat" test
  ```
* **Run static analysis:**
  ```powershell
  & "D:\flutter\bin\flutter.bat" analyze
  ```
* **Build with custom backend URL:**
  ```powershell
  & "D:\flutter\bin\flutter.bat" run --dart-define=API_BASE_URL="https://app.notenra.com/api"
  ```
