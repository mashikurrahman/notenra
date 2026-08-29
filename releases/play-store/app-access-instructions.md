# Google Play — App access (reviewer login) instructions

**Why this is mandatory:** Notenra is clinician-only with **no public sign-up**.
A Google reviewer who opens the app hits the login wall and can go no further. If
you don't give them a working login, the app is rejected as *"we were unable to log
in / complete the review."* This is the single most common rejection for gated
clinical apps.

Location in Console: **Play Console → App content → App access → "All or some functionality is restricted"**.

---

## What to enter in Play Console

Add one instruction entry:

- **Name / label:** `Clinician login`
- **Username:** `[DEMO CLINICIAN EMAIL]`
- **Password:** `[DEMO CLINICIAN PASSWORD]`
- **Any other instructions:**
  ```
  This app is for licensed clinicians only; there is no public sign-up.
  Sign in with the credentials above to reach the full app.
  All patient data visible in this account is fictitious test data — no real PHI.
  MFA is currently disabled for this account. Recording requires tapping
  "Record" on the Today tab and confirming the on-screen consent prompt.
  ```

> These credentials are visible only to Google's review team, not to the public.

---

## Choosing the demo account — do this the safe way

**Do NOT hand reviewers a real clinician's production account.** Use a dedicated
demo account that contains only fake patients. Two options:

### Option 1 (recommended) — ask the developer to create a clean demo clinician
Send the developer/admin this request:

> "Please create a dedicated **demo clinician account** on the production server for
> the Google Play review — role `clinician`, e.g. `demo@notenra.com`, with a fixed
> password, **MFA disabled**, and **first-login forced-password-change turned OFF**
> (so the reviewer isn't forced to change it). It should be isolated from any real
> clinic and contain only test patients."

The two "off" flags matter: if the account forces a password change or an MFA
enrollment on first login, the reviewer gets stuck. Confirm the account logs
straight into the main app.

### Option 2 — seed a test clinician yourself
Once the demo account exists but is empty, give it fictitious patients with
`tool/seed_patients.js`, which creates patients **and** their scheduled visits
(a patient with no visit row is invisible to the clinician):

```bash
node tool/seed_patients.js --base https://app.notenra.com/api --email <demo> --password <pw> --confirm
```

Seeded rows carry a `ZZTest` name/MRN prefix so they are identifiable and
removable later; every created id is appended to `tool/seeded-patients.log`.

Whichever option you use, put the account's email + password into the App access
fields above, and confirm it holds **no real patient data**.

---

## Before you submit — verify the demo login yourself
1. Install the exact build you're uploading (`Notenra-stable-v1.0.0.aab` → internal testing track).
2. Log in with the demo credentials on a clean device/emulator.
3. Confirm: login succeeds, **no** forced password change, **no** MFA screen, the Today
   tab loads, and "Record" → consent prompt → recording works.
4. Only then paste those same credentials into App access.

---

## Optional: I can seed fresh fake patients for the demo account
Once you tell me which email is the designated demo clinician (and confirm it's OK
to write test data to it), I can generate a clean set of clearly-fictitious patients
(obviously-fake names, no real MRNs) and sync them so the reviewer sees a realistic,
PHI-free app. Just say the word and give me the go-ahead.
