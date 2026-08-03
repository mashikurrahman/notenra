# Google Play — Store listing copy (paste-ready)

Location: Play Console → Grow users → Store presence → **Main store listing**.

> Notenra ships under a **new** application id (`com.notenra.notenra`), so Play
> treats it as a brand-new app: create a new Play Console entry rather than
> updating the predecessor listing.

## App name (max 30)
```
Notenra
```

## Short description (max 80)
```
Securely record clinical visits — your scribe team turns them into notes.
```
(72 characters)

## Full description (max 4000)
```
Notenra is a secure clinical documentation companion for licensed clinicians. Record a patient visit in a few taps; your organization's scribe team turns the audio into a clinical note that you review and approve — on your phone or in the web app.

Built for clinicians:
• Today view — see who's next, what's waiting on your review, and what's left of the day at a glance
• One-tap visit recording, with patient consent confirmed before capture
• Works offline — recordings upload automatically when you're back online
• Review completed notes and approve or request changes, with comments anchored to the exact sentence
• A day-by-day schedule you can search and reschedule from
• Reliable long recordings that keep going if the screen locks

Security and privacy first:
• Audio and clinical data encrypted on the device (AES-256) and in transit (TLS)
• Biometric-protected vault and automatic sign-out after inactivity
• On-screen patient information is protected from screenshots and screen recording
• Implements HIPAA technical safeguards

Important:
Notenra is intended for licensed clinicians and authorized staff of healthcare organizations that use the platform. It requires a clinician account provided by your organization — there is no public sign-up. Patient information is handled on behalf of your organization under a Business Associate Agreement.

The mobile app stays focused on fast, secure capture and review. The heavier work — transcription, note authoring, and record-keeping — happens on the web platform.
```

## Other store-listing fields
- **App category:** Medical
- **Tags:** medical records, health (pick from Play's list; avoid anything implying diagnosis)
- **Email address (support):** a monitored address  ← FILL a real one
- **Website:** your public Notenra site  ← FILL
- **Phone (optional):** leave blank unless you have a support line

## Graphics you must upload (required)
- **App icon** — 512×512 PNG (32-bit, the Notenra mark). Rendered by
  `node tool/render_brand.js` as `assets/images/notenra_icon.png` (1024×1024);
  downscale that to 512×512 for the store.
- **Feature graphic** — 1024×500 PNG/JPG (banner shown at the top of the
  listing). Use the full lockup, `assets/images/notenra_logo.png`, on white or
  on the brand gradient (blue `#2563EB` → `#15307A`).
- **Phone screenshots** — at least 2 (up to 8), 16:9 or 9:16, min 320px side.
  Capture from the running app — Today, the recorder, and a note review read
  best. Avoid showing real PHI: use the fake demo data.

> Tip: take screenshots from a demo account seeded with fictitious patients so
> no real PHI appears.
