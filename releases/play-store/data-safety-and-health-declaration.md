# Google Play — Data Safety form + Health apps declaration (fill-in sheet)

This is a copy-paste answer key for the two Play Console sections that trip up
health apps. Answers are derived from the actual app code (see notes). Anything
in **[BRACKETS]** is a decision only you can confirm.

Location in Console: **Play Console → App content → (1) Data safety, (2) Health apps declaration.**

---

## PART A — DATA SAFETY FORM

### A0. Overview questions
| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** (TLS/HTTPS enforced; cleartext disabled) |
| Do you provide a way for users to request that their data be deleted? | **Yes** — via the healthcare organization / by contacting the privacy address in the policy. Provide your deletion-request URL or email. |

### A1. Data types — what to declare as COLLECTED

For each type below: **Collected = Yes**, **Shared = No** (see note on "shared"),
**Processed ephemerally = No**, **Required (not optional) = Yes**,
**Purpose = App functionality** (and *Account management* where noted).

> **"Shared" = No** is correct: sending data to *your own* Notenra backend
> (a service provider under a BAA) is **not** "sharing" in Play's definition.
> Play "sharing" means transfer to a *third party* for their own use — which
> this app does not do.

| Data type (Play category) | Collected? | Why (purpose) | Source in code |
|---|---|---|---|
| **Health info** (health records) | Yes | App functionality | Patient name, MRN, DOB, age, gender, medical history, visit data (`Patient` model) |
| **Audio → Voice or sound recordings** | Yes | App functionality | Visit audio recordings (`Recording` model, `record` package) |
| **Personal info → Name** | Yes | App functionality, Account management | Clinician full name + patient name (`User`, `Patient`) |
| **Personal info → Email address** | Yes | Account management | Clinician sign-in username/email (`User.username`) |
| **Personal info → User IDs** | Yes | App functionality | Clinician ID / patient MRN in audit log (`AuditEntry`) |
| **Personal info → Phone number** | Yes | App functionality | Patient emergency contact phone (`Patient.emergencyContactPhone`) |
| **App activity → Other actions** | Yes | App functionality (security/audit) | Security audit trail (`AuditEntry`) |

### A2. Data types to declare as NOT collected (confirmed from `pubspec.yaml` — no such SDKs)
- **Location** — Not collected
- **Financial info** — Not collected
- **Messages / contacts / calendar** — Not collected
- **Photos / videos** — Not collected (only in-app audio)
- **App info & performance / crash logs / analytics** — Not collected (no analytics or crash SDK)
- **Device or other IDs / advertising ID** — Not collected (no ads, no tracking)

### A3. Security practices (Data safety → Security section)
| Question | Answer |
|---|---|
| Is data encrypted in transit? | **Yes** — TLS on all requests; `usesCleartextTraffic="false"` |
| Is data encrypted at rest? | **Yes** — SQLCipher DB + AES-GCM audio vault; keys in hardware-backed keystore |
| Can users request data deletion? | **Yes** — via healthcare org / privacy contact |
| Committed to Play Families policy? | **No** (not a children's app) |
| Independent security review? | **[Optional — answer "No" unless you have a formal third-party audit report]** |

### A4. Biometrics note
Do **not** declare biometric data as collected. Fingerprint/face is handled by the
OS `local_auth` API; the biometric never reaches the app or your servers. Only the
*result* (unlock succeeded/failed) is used locally.

---

## PART B — HEALTH APPS DECLARATION

Google requires this for apps in the Medical / Health & Fitness space that access
health data. Suggested answers:

| Prompt | Answer |
|---|---|
| App category | **Medical** |
| Does the app handle personal health data / medical records? | **Yes** |
| Intended users | **Licensed healthcare professionals / clinical staff only** (not general public) |
| Is it a medical device / does it make diagnostic claims? | **No** — it is a clinical **documentation** aid; it does not diagnose, treat, or make medical decisions. |
| How is health data protected? | Encrypted in transit (TLS) and at rest (SQLCipher + AES-GCM); access restricted to authenticated clinicians; automatic sign-out; screenshot/secure-window protection; audit logging. |
| Is the developer authorized to handle this health data? | **Yes** — under Business Associate Agreements with the healthcare organizations that use the app. |
| Consent for recording | Patient consent is confirmed in-app before any recording begins. |
| Data sharing with third parties | **None** for third-party purposes; data goes only to the organization's own secure backend. |

> If Console asks for **regulatory context**: this is a HIPAA-oriented workflow tool
> operating as a business associate; it is **not** an FDA-regulated medical device and
> makes no diagnostic/therapeutic claims. Do not overstate — claiming "medical device"
> triggers stricter review you don't need.

---

## PART C — APP ACCESS (reviewer login) — see `app-access-instructions.md`
Play reviewers cannot self-register (clinician-only, no public sign-up), so you MUST
provide working demo credentials in **App content → App access**, or the app will be
rejected as "unable to complete review."

---

## Quick pre-submit checklist
- [ ] Privacy Policy hosted at a public URL and pasted into App content
- [ ] Data safety form completed per Part A and **published**
- [ ] Health apps declaration completed per Part B
- [ ] App access demo credentials provided (Part C)
- [ ] Content rating questionnaire completed (category: Medical; audience: adults)
- [ ] Target audience set to adults (not children)
- [ ] Store listing: no misleading medical/diagnostic claims
