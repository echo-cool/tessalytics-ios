# Tessalytics 1.2.1 — App Store Connect Submission Kit

App `6803221525`, bundle `com.echocool.Tessalytics`, team `P8FYZDZ6AA`.

This release makes the app reviewable without a TeslaMate server. The whole
point of the kit is `metadata/review_notes.txt`: it tells App Review to tap
**Explore Demo** instead of asking for a server URL and a bearer token, which is
what the previous notes did and what would have stalled a review.

## Status

| | |
|---|---|
| Build | `202608192006`, marketing version `1.2.1` |
| Archive | `build/Tessalytics-1.2.1-202608192006.xcarchive` |
| Uploaded | 2026-08-19 20:09 PDT, `** EXPORT SUCCEEDED **` / "Upload succeeded" |
| Auth | Xcode's signed-in developer account (no API key needed for the upload) |
| Tests | `TessalyticsTests` 40 passed, 3 skipped (live-server suite), 0 failures |
| Encryption | `ITSAppUsesNonExemptEncryption = false` confirmed in the archive |
| TestFlight | `VALID`, registered 20:09 PDT — available for internal testing |
| TestFlight notes | pushed, `betaBuildLocalization d75752e6` |
| Review notes | pushed, `appStoreReviewDetail 83e32908` (2,857 chars) |
| URLs | pushed — privacy on the app info record, support/marketing on 1.1.0 |
| What's New | **held back** — ASC rejects `whatsNew` on an initial store version |

## What's new since the uploaded trains

The previous uploads were 1.1.0 build 5 (selected for the App Store version) and
the 1.0.3 TestFlight train `202608191804`. 1.2.1 carries the demo experience,
the status cache, and the compatibility and unit-formatting work:

- `Tessalytics/Core/Demo/DemoExperience.swift` — generated on-device demo
- `Tessalytics/Core/Synchronization/VehicleStatusCache.swift` — cached status
  first, deduplicated refresh behind it, so a slow server cannot block the
  dashboard or pull-to-refresh
- Freshness labels, Activity route previews and incremental loading, dashboard
  and navigation polish, TeslaMateApi compatibility, metric-unit clarity
- A published privacy policy and support page at `tessalytics.echo.cool`

## What this kit changes, and what it deliberately does not

New copy: `review_notes.txt`, `whats_new.txt`, `testflight_whats_new.txt`, and
the three URL files — the URLs moved off GitHub onto the new site, which is the
change that unblocks the privacy-policy requirement.

**Unchanged and already live in App Store Connect from 1.1.0**: name, subtitle,
description, keywords, promotional text, copyright, categories, age rating,
content rights, price, and the App Privacy answers (Data Not Collected). This
kit does not duplicate them; `app-store/metadata/en-US.json` remains the
reference. `asc.py` skips a field whose file is absent, so nothing is
overwritten with a stale copy.

To push this kit's copy and inherit the rest, chain the directories:

```sh
ASC_METADATA=release/tessalytics-1.2.1/metadata:app-store/metadata
```

## Pushing it — needs the issuer ID

`~/.appstoreconnect/private_keys/AuthKey_6XCPQNJPCG.p8` is on this machine and
the issuer ID is beside it in `~/.appstoreconnect/issuer_id` (mode 600). Neither
is in the repo, and neither belongs in one:

```sh
export ASC_ISSUER_ID=$(cat ~/.appstoreconnect/issuer_id)

./scripts/asc.py show               # confirm which version record is editable
./scripts/asc.py builds             # wait for 202608192006 to reach VALID
./scripts/asc.py push-beta-notes    # TestFlight "What to Test"
./scripts/asc.py push-review-notes  # the demo-mode App Review notes
./scripts/asc.py push-locale en-US  # whatsNew + the three new URLs
```

Registration is slow and looks like failure: for most of the wait a build is
absent from `GET /builds` in **every** state, so an upload that vanished and an
upload that is merely slow are indistinguishable. Give it twenty minutes before
concluding anything. `push-beta-notes` fails with a clear message until the
build appears.

Nothing in `asc.py` submits for review. Add for Review and Submit stay manual.

## Build 5, selected for 1.1.0, has expired

`GET /builds` reports build `5` as `expired: true`. It is the build currently
selected on the 1.1.0 version record, and an expired build cannot be submitted —
so selecting `202608192006` is no longer a matter of preference. Build
`202608191804` and `202608192006` are the only unexpired recent builds.

## The version record needs a decision first

App Store Connect keeps **one editable version per app**, and right now that is
**1.1.0 in `PREPARE_FOR_SUBMISSION` with build 5 selected** — prepared but never
submitted. So `create-version` will most likely be rejected: there is nowhere to
put a second editable version.

Because 1.1.0 was never submitted, the cheap fix is to **rename it**: open the
version page in App Store Connect and change the version number to `1.2.1`, then
select build `202608192006` under Build. No queue position is lost, because none
was ever taken. `push-review-notes` and `push-locale` then land on that record,
and `version_id()` finds it by matching `metadata/version.txt`.

The alternative — leaving 1.1.0 as the store version and treating 1.2.1 as a
TestFlight-only train — is also fine, and is what happened to 1.0.3. In that
case push only `push-beta-notes` and leave the store metadata alone.

## Still only a person can do these

- Rename the 1.1.0 version record to 1.2.1 (or decide to keep 1.2.1 on
  TestFlight only), then select build `202608192006`.
- Re-shoot the five 6.9-inch screenshots if any captured screen changed in this
  build. The current set in `app-store/screenshots/en-US/6.9-inch/` was taken
  from the demo data, and a screenshot that no longer matches the app is a
  rejection. The dashboard and Activity both changed here — check before
  submitting.
- Finish the open visual QA items in `docs/app-store-checklist.md`: dark mode
  and large Dynamic Type, and the VoiceOver walkthrough.
- Add for Review and Submit.

## The review notes no longer ask for a server

`app-store/review-notes.md` used to open with a review-server URL and a bearer
token to be pasted into App Store Connect. Those placeholders were never filled,
and a reviewer who cannot reach a server cannot get past onboarding — the app
would have come back rejected for a reason that has nothing to do with the app.
`metadata/review_notes.txt` replaces that with demo mode, which needs no server,
no account, no credentials, and no network. The server instructions are still in
`app-store/review-notes.md` as a fallback if a reviewer asks for a real
connection.
