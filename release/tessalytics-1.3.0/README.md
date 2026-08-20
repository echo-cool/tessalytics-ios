# Tessalytics 1.3.0 — TestFlight Kit

App `6803221525`, bundle `com.echocool.Tessalytics`, team `P8FYZDZ6AA`.

1.3.0 adds native iPad support and stops the dashboard presenting TeslaMateApi's
missing-data placeholders as measurements. The upload is a TestFlight train; no
store version record was created or renamed.

## Status

| | |
|---|---|
| Build | `202608192324`, marketing version `1.3.0` |
| Archive | `build/Tessalytics-1.3.0-202608192324.xcarchive` |
| Uploaded | 2026-08-19 23:28 PDT, `** EXPORT SUCCEEDED **` / "Upload succeeded" |
| Auth | Xcode's signed-in developer account (no API key needed for the upload) |
| Tests | `TessalyticsTests` 47 passed, 3 skipped (live-server suite); `TessalyticsUITests` 13 passed |
| Device family | `UIDeviceFamily [1, 2]` verified in the archive — iPhone **and iPad** |
| Encryption | `ITSAppUsesNonExemptEncryption = false` verified in the archive |
| Deployment target | iOS 18.0 |
| TestFlight | `VALID`, registered 23:28 PDT — available for internal testing |
| TestFlight notes | pushed, `betaBuildLocalization 92bf1cbf` (2,390 chars) |
| Review notes | unchanged, inherited from the 1.2.1 kit |
| Store metadata | untouched — there is no editable version record, see below |

## Why the version went to 1.3.0 rather than 1.2.2

`TARGETED_DEVICE_FAMILY` moved from `"1"` to `"1,2"`. Adding a device family is a
feature release, not a patch, and it gives the iPad work its own TestFlight
train instead of burying it in a point release. 1.2.1 build `202608192006` — the
build prepared for the store version record — is untouched and still selectable.

## What shipped

**Correctness.** The status endpoint answers from the last vehicle poll, and
while a car is asleep TeslaMateApi emits Go zero values rather than nulls:
`locked: false`, `est_battery_range: 0`, `charge_limit_soc: 0`,
`charging_state: ""`, every tyre at `0`. The previous build rendered them
verbatim, so it told the owner a locked car was unlocked and a battery at 80%
had no range left. `Tessalytics/Core/Models/StatusInterpretation.swift` filters
every live reading:

- range falls back `est → rated → ideal` and the label names which figure it is
- lock and opening state read "Unknown" while the car is asleep, with the reason
  stated on the card, instead of asserting a false negative
- zero-valued charge limit, power, energy and tyre pressures read "Not
  reported"; empty strings are not treated as states
- the model code `"3"` expands to "Model 3"

`TessalyticsTests/OfflineTelemetryTests.swift` pins all of it to a fixture
shaped like a real sleeping-car payload. Its identifying fields are scrubbed —
no VIN, car name, address or hostname belongs in this repo.

**Status polling never started after setup.** `saveProfile` set `phase = .ready`
before the vehicle list loaded, so the dashboard's `.task` called
`startStatusPolling()` while `selectedVehicle` was still nil, the guard
rejected it, and nothing retried. The poller now records its target vehicle and
retargets when the selection changes instead of silently no-oping.

**Pull to refresh could stick open.** The action fired two detached tasks and
slept 350 ms, so it reported completion before any data arrived, and
`.refreshable` was attached outside the scroll view. It now awaits the real work
and is attached to the scroll view that owns it, on Status and both Activity
tabs.

**Swipe-back was disabled on the detail screens.** They drew a custom back
button, which needs `navigationBarBackButtonHidden(true)` — and that also kills
the interactive edge-swipe gesture. Both now use the system back button.
`testDriveDetailPushesBackWithSystemControlAndSwipe` covers the button and the
gesture.

**Drive list performance.** Every row hosted a live `MKMapView`. Routes are now
`MKMapSnapshotter` bitmaps cached in an `NSCache`, composited off the main
actor, and rendered at 160pt instead of 82pt.

**iPad.** `.tabViewStyle(.sidebarAdaptable)` for a real sidebar, all four
orientations, and content held to a readable width so cards do not stretch
across thirteen inches.

**Presentation.** One `TessalyticsLayout` replaces grid definitions that ranged
across min widths of 92/104/110/132/140 and spacings of 7/8/10/12. Metric cards
fill their grid row, so a tile with a longer title no longer stands taller than
its neighbours. Charts name both axes with units, label their values and carry
legends; drive and charge charts plot against time rather than `detailId`. Home
screen cards are tappable and lead to the matching detail screen. Charging rows
lead with energy added and average power and show a price only where one is
configured.

Also fixed: `ping()` sent no credentials, so the connection test failed behind
an authenticating reverse proxy; the analysis-mode chips had their padding
outside the `Button`, leaving only the text tappable; software updates were not
sorted; a charge cost of `0` read as `$0.00`.

## Pushing the TestFlight notes — needs the issuer ID

The `.p8` is at `~/.appstoreconnect/private_keys/AuthKey_6XCPQNJPCG.p8` and the
issuer ID beside it in `~/.appstoreconnect/issuer_id`. Neither is in the repo.

```sh
export ASC_ISSUER_ID=$(cat ~/.appstoreconnect/issuer_id)
export ASC_METADATA=release/tessalytics-1.3.0/metadata:release/tessalytics-1.2.1/metadata:app-store/metadata

./scripts/asc.py builds             # wait for 202608192324 to reach VALID
./scripts/asc.py push-beta-notes    # TestFlight "What to Test"
```

Chaining the 1.2.1 kit behind this one inherits the demo-mode review notes and
the URLs; this kit carries only `version.txt`, `build.txt` and
`testflight_whats_new.txt`, so nothing else can be overwritten with a stale
copy.

Registration is slow and looks like failure — for most of the wait the build is
absent from `GET /builds` in every state, so a lost upload and a slow one are
indistinguishable. Give it twenty minutes. `push-beta-notes` fails with a clear
message until the build appears.

## Deliberately not done

- **No store metadata push, and none is possible.** `1.2.1` is
  `WAITING_FOR_REVIEW` as of this upload — the decision the 1.2.1 kit left open
  was taken, and 1.2.1 was submitted. App Store Connect keeps one editable
  version per app, and a version in review is not it, so there is nowhere for
  store copy to land. `whats_new.txt` is therefore absent from this kit by
  design rather than by omission. When 1.2.1 clears review, 1.3.0 needs a
  version record created (`create-version`) before any store copy can be pushed.
- **No screenshots.** The 6.9-inch set in `app-store/screenshots/en-US/6.9-inch/`
  predates this build and the dashboard, Activity and chart screens all changed
  — a screenshot that no longer matches the app is a rejection. iPad screenshots
  do not exist at all and are **required** once the build declares iPad support.
  Neither blocks TestFlight.
- **No review submission.** Nothing in `asc.py` submits; Add for Review and
  Submit stay manual.

## Still only a person can do these

- Re-shoot iPhone 6.9-inch screenshots, and shoot the iPad 13-inch set, before
  any store submission of an iPad-capable build.
- Verify on real hardware that a genuinely asleep car shows "Unknown" lock state
  and a rated-range fallback. This was validated against the captured payload
  and a new `-ui-demo-offline` flag, not against a live server in-app.
- Finish the visual QA items in `docs/app-store-checklist.md`: dark mode, large
  Dynamic Type, and the VoiceOver walkthrough — now on iPad as well as iPhone.
