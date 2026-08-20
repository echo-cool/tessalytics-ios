# Tessalytics 1.5.0 (202608200407)

TestFlight-only build on the 1.5.0 train. No store copy changed, so this kit
carries only `build.txt`, `version.txt` and the TestFlight notes; chain it ahead
of `app-store/metadata` to inherit everything else.

    ASC_METADATA=release/tessalytics-1.5.0-b202608200407/metadata:app-store/metadata

## What shipped

Chart correctness, and the sync fault behind the spurious offline state.

- **Area marks stacked.** `AreaMark` stacks by default in Swift Charts, so a
  dense single series summed neighbouring samples: a drive peaking at 33 mph drew
  spikes to 155 against its own "Maximum speed 33 mph" card. Fixed with
  `stacking: .unstacked` in both `DriveDetailView` and `ChargeDetailView`.
- **Zero-anchored axes for readings where zero is meaningless.** `ChartBaseline`
  distinguishes a magnitude (speed, power, energy — keeps zero, keeps the fill)
  from a reading framed to its own range (elevation, outside temperature, pack
  voltage). An area mark implies a zero baseline, so the focused case draws the
  line alone.
- **Odometer domain on the capacity chart.** A car logged from 15,000 miles was
  spending two thirds of the plot on mileage with no readings.
- **Cursor pagination broke on page 2.** Every TeslaMate timestamp column is
  `timestamp without time zone`; once the backend started emitting `+00:00` the
  cursor carried an aware datetime and asyncpg refused it. Drives stopped at 100
  of 798, charges never ran, and that throw raised the "Offline" banner and
  "Stale" badge against a healthy server. Fixed in the backend's `pagination.py`
  with a coercion backstop at `db.fetch`.
- **Independent sync legs.** A drive-paging failure no longer costs the charge
  history, and a partial pass is not marked synced — marking it would flip later
  runs to incremental and leave the gap permanent.
- **Sub-second timestamps survive the cache.** `FlexibleDate.encode` used a
  default `ISO8601DateFormatter`, which writes whole seconds, so a drive's 747
  position samples became 211 instants on the way through `DetailCacheRecord`.
  Charts dropped marks and drew a self-intersecting fill.
- **Dense series are decimated** to a few hundred marks, min and max per bucket
  so peaks survive. Past a few hundred marks Swift Charts truncated the trace
  partway across the plot.
- **Short addresses.** The backend composes `name/road, city` the way TeslaMate's
  own dashboards do, and keeps the full OSM string as `address_full`.
- **Less text.** Chart paragraphs, the Settings footer and the analytics captions
  are gone; period deltas read `+78% vs prev. 30d` instead of truncating.

## Verification

- 111 unit tests and 13 UI tests pass. The live-server cases now genuinely run:
  they read their credentials from the test process, so they need a
  `TEST_RUNNER_` prefix on the `xcodebuild test` command line or they silently
  `XCTSkip`. Two of them previously aimed the legacy client at the new API; they
  probe for the server kind now, the way the app does.
- Backend: 120 tests, ruff clean, redeployed. All 798 drives page through and
  match `SELECT count(*) FROM drives WHERE car_id=1` exactly.
- Verified in the simulator against the live backend, not fixtures.

## Still blocked for the store

App Store screenshots are stale and there is no iPad set. An iPad-capable build
cannot be submitted without one. Neither blocks TestFlight.
