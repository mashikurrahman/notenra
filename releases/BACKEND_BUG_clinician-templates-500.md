# Backend bug report — `clinician-templates` returns 500

**For:** the `noterna-backend` web-app developer
**Filed:** 2026-09-01 · **Status:** open (re-verified 2026-09-01, still failing)
**Severity:** blocks the mobile app's note-templates feature (degrades to on-device fallback)

## Summary

`GET /api/settings/clinician-templates` returns **HTTP 500** `{"error":"Something went wrong"}`
on production for an authenticated clinician. The route is documented in the API
reference (seeds 4 default templates — New Patient, Follow-Up, Virtual Visit,
Other — on first access) but errors before returning them.

## Evidence

Tested against `https://app.notenra.com/api` with a valid clinician session
(role = `clinician`, full session — no gate):

| Request (same session cookie) | Result |
|---|---|
| `GET /api/auth/me` | **200** ✅ |
| `GET /api/settings/public` | **200** ✅ |
| `GET /api/settings/clinician-templates` | **500** ❌ `{"error":"Something went wrong"}` |

Because `/auth/me` and `/settings/public` succeed with the same session, this is
**not** an auth, CSRF, or session problem — it is specific to this route.

## Reproduction

1. `GET /api/csrf-token`
2. `POST /api/auth/login` with a clinician's email + password → full session cookie.
3. `GET /api/settings/clinician-templates` with that session → **500**.

## Most likely cause

The route (controller: `clinicianTemplatesController`) seeds 4 default templates
on first access. The failure is probably in that seed path or the underlying
table — e.g.:

- the `clinician_note_templates` table is **not migrated on production**, or
- a column mismatch / constraint in the seed `INSERT`, or
- the seed-on-first-access throws and isn't caught.

**Action:** check the production server logs for the stack trace on this route,
and confirm the `clinician_note_templates` table exists and is migrated in prod.

## Also verify once GET is fixed

The mobile app also calls these (same auth):

- `POST /api/settings/clinician-templates` — replace the full template set.
- `DELETE /api/settings/clinician-templates/:id` — delete one template.

Please confirm all three return 200 with the documented shapes.

## Impact / current mitigation

The mobile note-templates feature (Profile → Note templates) is built against
this contract and works, but because the endpoint 500s it currently runs on an
**encrypted on-device cache** seeded with the 4 default templates. Local edits
are held and will **auto-sync** to the server as soon as GET/POST/DELETE return
200 — no mobile-app change needed once the backend is fixed.
