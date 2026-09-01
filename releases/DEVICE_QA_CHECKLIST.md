# Notenra — Pre-Release Device QA Checklist

Run this on a **physical Android device** (and iOS via TestFlight) against the
**live** backend before shipping. Unit tests and emulators do **not** exercise
the native mic recorder, biometric vault, Android foreground service, or
hardware-backed secure storage — those only work on real hardware.

**Build under test:** the production artifact must be built with
`--dart-define=DEMO_ACCOUNTS=false` (real clinician login, no seeded demo data).
Confirm there is **no** "Demo build" banner and **no** fake patients on first run.

**Login for QA:** a real clinician account on the live server (e.g. the AI-only
test clinician). There are no built-in demo logins in a production build.

---

## 1. Install & launch
- [ ] Install the signed release AAB/APK on a real device.
- [ ] App launches to the splash → login (no white screen, no startup error snackbar).
- [ ] No "Demo build" indicator anywhere; patient list is empty until login.

## 2. Authentication & vault
- [ ] Log in with a real clinician email + password against the live server.
- [ ] Any required gates complete (forced password change / PHI training / MFA).
- [ ] Biometric vault prompt appears after login; Face ID / fingerprint unlocks it.
- [ ] "Use password instead" fallback unlocks the vault.
- [ ] Leave the app idle past the auto-logoff timeout → vault re-locks on return.
- [ ] Sign out → in-memory PHI is cleared (patient list empty on next login screen).

## 3. AI-only flow (record → note → finalize)  ← the new feature
- [ ] Open a patient → tap Record. **Mic permission** is requested and granted.
- [ ] The persistent **"● Recording"** foreground notification appears (Android);
      the in-app recording banner shows and the timer counts up.
- [ ] Lock the screen / background the app mid-recording → capture continues
      (foreground service not killed); returning shows the elapsed time.
- [ ] Stop → dialog says the AI note is generated automatically (no scribe wording).
- [ ] The visit banner shows **"AI Generating Note…"** / "View Progress".
- [ ] Within ~1–2 min the banner flips to **"AI Clinical Note Ready"** / **Review Note**
      *without* manually refreshing (the poll + auto-fetch drives it).
- [ ] Open the note: the **7 real sections** render as tabs (Chief Complaint / HPI /
      PE / Imaging / A&P) and **ICD-10 / E&M code chips** appear and copy on tap.
- [ ] Compare the note against the **web app** for the same visit — they match.
- [ ] Edit the note → Save edits → text persists.
- [ ] **Finalize & Lock** → confirm dialog → status becomes locked; note is read-only;
      "Request changes" is **not** offered (AI-only has no scribe). Confirm the web
      app shows the visit as locked/uploaded.

## 4. Multiple recordings on one visit
- [ ] Record a second clip for the same patient → it **appends** to the same visit
      (one patient card, "2 recordings"), not a duplicate visit.

## 5. Note templates (Profile → Note templates)
> The server endpoint currently 500s, so expect the **"working from your device
> copy"** banner. Verify the on-device behaviour holds:
- [ ] The 4 default templates show (New Patient, Follow-Up, Virtual Visit, Other).
- [ ] Edit a template's name/content → Save → change persists **after app restart**.
- [ ] Create a new template → it appears in the list.
- [ ] Delete a template → it's removed.
- [ ] Reset to defaults → the 4 defaults return.
- [ ] (After the server is fixed) reopen → local edits sync up; banner clears.

## 6. Offline / sync resilience
- [ ] Turn on airplane mode, record a visit, stop → recording is **queued** (not lost).
- [ ] Re-enable network → the queued audio uploads on its own; status advances.
- [ ] Kill and relaunch the app with a pending upload → it still completes (outbox
      survives restart), and the recording is **not** uploaded twice.

## 7. Security posture
- [ ] Attempt a screenshot → blocked on device.
- [ ] No patient names / note text appear in `adb logcat` (release logging is off).

## 8. Notifications
- [ ] "Recording uploaded" notification fires after an upload.
- [ ] "Note ready" notification fires when a note becomes ready for review.

---

### Sign-off
- Device(s) tested: ____________________  OS versions: ____________________
- Build version: 1.0.x+__   Backend: https://app.notenra.com/api
- Tester: ____________________   Date: ____________________
- Result: ☐ Pass  ☐ Pass w/ notes  ☐ Fail — notes: ____________________
