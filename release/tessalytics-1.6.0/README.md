# Tessalytics 1.6.0 (202608201258)

Chain this kit ahead of `app-store/metadata` so unchanged store copy is inherited
rather than overwritten:

    ASC_METADATA=release/tessalytics-1.6.0/metadata:app-store/metadata

## What shipped

The app speaks only Tessalytics Backend now. The TeslaMateApi client and the
server-kind detection that chose between them are gone: one code path instead of
two, and no more fixing everything twice.

- **Owner-supplied vehicle rating.** Every as-new figure was derived from the best
  the recorded history could support, which is wrong whenever logging began after
  the pack had aged — an 84 kWh car reads as 74 if TeslaMate started at 15,000
  miles, and health, capacity lost, range lost and equivalent cycles all inherited
  it. Settings > Vehicle > Vehicle rating takes the real figures.
- **Hero card rebuilt.** No more "Offline at ...": a car is parked or asleep
  almost all the time, so that spent the most prominent line in the app on the
  least surprising fact. Battery is a ring, the odometer sits beside the range,
  and a bottom band carries a seven-day strip, typical consumption and health.
- **Places draws the real route.** A new `/v1/vehicles/{id}/track` endpoint
  aggregates 1.7M position rows server-side into simplified polylines, one per
  journey. Joining drive endpoints had been cutting straight chords through the
  hills.
- **Charts are explorable.** Touch and hold for a pivot line and readout, switch
  between line, bar, area and pie, read the series as a table.
- **Chart correctness.** `AreaMark` stacks by default, so a drive peaking at
  33 mph drew spikes to 155; sub-second timestamps were lost through the local
  cache, collapsing 747 samples onto 211 and silently dropping marks; and value
  axes now only include zero where zero is a floor.

## Store submission

Submitted. Build `202608201258` as 1.6.0, `WAITING_FOR_REVIEW`.

The 1.2.1 submission was withdrawn first: App Store Connect keeps one editable
version per app, so a queued submission blocks store copy for everything behind
it. The 1.2.1 record was renamed to 1.6.0 rather than adding a version, which is
the normal flow.

Both screenshot sets were re-captured from demo mode — the previous iPhone set
predated this release's home screen, and an iPad-capable build cannot be
submitted without an iPad set at all. `ScreenshotCaptureTests` takes them, so the
next release is one command rather than a manual pass.

`scripts/asc.py` gained `push-screenshots`, `review-status`, `withdraw-review`,
`submit-for-review` and `prepare-version` to do all of this.

## Verification

- 122 unit tests and 13 UI tests. The live-server cases need a `TEST_RUNNER_`
  prefix on the `xcodebuild test` command line or they silently skip.
- Backend: 129 tests, ruff clean, deployed. All 798 drives page through and match
  `SELECT count(*) FROM drives WHERE car_id=1` exactly.
- Verified in the simulator against the live backend rather than fixtures.
