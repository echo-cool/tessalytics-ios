# Tessalytics 1.4.0 — TestFlight Kit

App `6803221525`, bundle `com.echocool.Tessalytics`, team `P8FYZDZ6AA`.

1.4.0 makes the app fetch on open and poll while foregrounded, and adds
fleet-wide statistics derived from the complete history rather than the newest
page. TestFlight train only; `1.2.1` is still the version in review.

## Status

| | |
|---|---|
| Build | `202608200133`, marketing version `1.4.0` |
| Archive | `build/Tessalytics-1.4.0-202608200133.xcarchive` |
| Uploaded | 2026-08-20 01:39 PDT, `** EXPORT SUCCEEDED **` / "Upload succeeded" |
| TestFlight | `VALID`, registered 01:40 PDT |
| TestFlight notes | pushed, `betaBuildLocalization 9b05bbb3` (2,437 chars) |
| Tests | `TessalyticsTests` 65 passed / 3 skipped; `TessalyticsUITests` 13 passed |
| Device family | `UIDeviceFamily [1, 2]` verified in the archive |
| Encryption | `ITSAppUsesNonExemptEncryption = false` verified |
| Store metadata | untouched — `1.2.1` is in review, so there is no editable record |

## What shipped

**Stale data on open.** `loadRecentDrives` only reached the server when the cache
was empty; otherwise it read SwiftData and stopped. That is why "Latest drive"
could be days old. The app now fetches on every foreground entry, and polls on two
cadences — live status every 30s, history every 5 minutes — both stopping when the
app backgrounds.

**Fleet-wide totals.** `FleetHistorySync` pages the entire drive and charge
history on first run (eight requests for ~800 drives at `show=100`), then tops up
with the newest page. Lifetime figures need every session and TeslaMateApi has no
aggregate endpoint.

**New on the home screen**: battery health in the top card (capacity new/now, max
range new/now, range lost); drive stats (logged, odometer, data lost measured from
the first logged drive); charging totals (charges, cycles, energy added/used,
efficiency, cost, promoted to MWh past 1,000 kWh).

**New charts**: battery capacity by mileage (per-charge scatter plus semi-monthly
median, both of the dashboard's SQL variants); projected range over time; charging
by location on a map weighted by energy.

**Under-decoded API.** Charges already return `range_rated`, `range_ideal`,
`odometer`, `latitude/longitude` and `battery_details`; drives return usable levels
plus `reduced_range` and `is_sufficiently_precise`; charge samples carry
`battery_info.rated_battery_range`. None of it was being read. Decoding it is what
made the capacity model possible without a backend.

Capacity model verified against real data: a charge at 272.51 mi rated range and
83%, with `rated_efficiency` 13.6 kWh/100 km, models 71.9 kWh against the
`/battery-health` figure of 72.35 kWh usable — within one percent.

## Not in this build

- **No Tessalytics-API integration.** The new backend is deployed and serving 182
  queries, but the app still reads TeslaMateApi only. Wiring it up is next.
- **No screenshots.** The 6.9-inch set predates these screens and no iPad set
  exists. Both required before any store submission of an iPad-capable build.
- **Not verified against a live server in-app.** Tested against captured payloads,
  demo data and the `-ui-demo-offline` flag.

## Pushing the notes

```sh
export ASC_ISSUER_ID=$(cat ~/.appstoreconnect/issuer_id)
export ASC_METADATA=release/tessalytics-1.4.0/metadata:release/tessalytics-1.3.0/metadata:release/tessalytics-1.2.1/metadata:app-store/metadata
./scripts/asc.py push-beta-notes
```

Only `version.txt`, `build.txt` and `testflight_whats_new.txt` live here; the
chain inherits the demo-mode review notes and URLs from the earlier kits.
