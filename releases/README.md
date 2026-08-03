# Notenra — Release folders

Two folders, one rule.

> **Fresh version history.** Notenra ships under a new application id
> (`com.notenra.notenra`), so the stores see a brand-new app and versioning
> restarts at `1.0.0+1`. The release history of the predecessor app
> (`com.anothealth.anot_scribe`, up to `1.2.2+5`) lives in that project and is
> **not** carried over here — its build artifacts are not interchangeable with
> these, and neither store will accept them under the new id.

## `stable/` — PRODUCTION. Locked. Do not overwrite.
The known-good build approved for production. Nothing changes here unless the
**user explicitly says "update the stable version."**

- _(no stable build yet — the first Notenra release will be
  `Notenra-stable-v1.0.0.apk` / `.aab`, app version `1.0.0+1`)_

## `dev/` — work in progress.
Every new change is built here first. NOT production until promoted.

- _(no dev build yet)_

## Promotion rule
When the user says **"update the stable version"**, copy the chosen `dev/` APK
into `stable/` with a bumped version label, commit + push the code, and record
the version/date here. Until then, `stable/` stays untouched.

## Inherited behaviour

Everything the predecessor app shipped through `1.2.2+5` is present in this
codebase — clinician-only login, the first-login security flow (forced password
change, PHI training acknowledgement, TOTP MFA), CSRF double-submit, consent
before the mic, PHI-free notifications, background-isolate encryption, recovery
of interrupted recordings, and the session-revalidation fix that stops a stray
401 during a long recording from signing the clinician out. Notenra adds the
rebrand and the Today / Schedule / Notes restructure on top of that.
