# Tessalytics 1.9.5 (202608250059)

TestFlight build. 1.6.0 still holds the editable version record
(`WAITING_FOR_REVIEW`), so this train carries beta notes only.

    ASC_METADATA=release/tessalytics-1.9.5/metadata:app-store/metadata

Uploaded 2026-08-25 01:04:07 US/Pacific from `main` at `ee7e8a4`, archived
Release, `destination: upload`. Build resource
`12f7eb2f-1d67-42d3-a185-c8a0dbc2f15f`, processed `VALID` with no errors or
warnings, `internalBuildState IN_BETA_TESTING`, `externalBuildState
READY_FOR_BETA_SUBMISSION` (not submitted). TestFlight expiry 2026-11-23. Export
compliance exempt (`usesNonExemptEncryption = false`). Minimum iOS 18.0. Beta
notes pushed to `betaBuildLocalization 564a6b2d-a4c2-42b8-8ecc-5edc1563b8bf`.
`metadata/` holds beta notes only — nothing in the store copy changed.

## What changed since 1.9.4

### 1.9.4's share fix traded one complaint for another

1.9.4 stopped the share button spinning by refusing to wait more than 1.5 s for
map tiles. Reported straight back: on a slower connection the poster came out
with a grey "route not available" panel where the map belongs. Quick and wrong is
not an improvement on slow and right, and the 1.9.4 kit had already flagged that
1.5 s was calibrated against simulator numbers and might be too low. It was.

The mistake was one number doing two jobs. There are two now:

| situation | wait | outcome |
| --- | --- | --- |
| no map cached at all | up to 5 s | waits — a poster missing its picture is worse than a slow one |
| a usable map cached | 400 ms | draws what it has, refreshes behind |

Waiting is not the answer either, so the maps are now fetched **while the home
screen is simply being read**: debounced on settled inputs, deduped by the
rounded key, and skipped while the car is driving, where the trail moves with
every reading and a fetch per reading would be spent on a map nobody asked for.
That is what makes a share both immediate and complete, which no single timeout
could.

Measured against an injected three-second-slow tile server:

- cold, prefetch disabled: `prepare=3.87 s`, map present
- prefetched: `prepare=0.021 s`, map present

### The cost, stated

The app now fetches one small map snapshot per distinct map while the home screen
is open, whether or not the owner ever shares. That reverses the note this code
used to carry — "a page nobody shares should not be downloading anything" — and
the reversal is deliberate, because that note is what made the poster come out
broken. Correctness does not depend on the prefetch: the cold budget is the
backstop, so it can be dropped for a slower first share if the network spend is
not wanted.

One honest gap: during testing the prefetch failed to fire once and did not
reproduce. The consequence is bounded — that run falls through to the cold path
and still produces the map.

### The hero chart has two axes

Battery percentage on the left in green, odometer on the right in grey and
dashed, over the same seven days. Axis labels are coloured to their series, which
says which side belongs to which without a legend taking a third of the card.

Swift Charts has one y scale per plot, so the odometer is mapped onto the
battery's domain to be drawn and the trailing axis is labelled with the reading
each position stands for. `unmapped` is the exact inverse of `mapped`, so a label
always names the value the dashed line sits at; positions outside the odometer's
band are left unlabelled rather than extrapolated into a reading the car never
showed. The band is inset from both ends of the domain, because mapped to the
full height the line's stroke sits half off the plot at the newest reading.

`OdometerHistory` reads the odometer from both ends of every drive and from
charging sessions — the only places TeslaMate records it — closes the series with
the live reading, and drops anything that would take the line backwards.

## Verification

- 482 unit tests, 0 failures.
- 71 UI tests. One run had three failures in `testOwnerTokenConnectionScreen`,
  which touches neither the chart nor the map; it passed alone and its whole
  class passed 14/14 on a re-run. Same signature as the `WebPairingUITests` flake
  in the 1.9.3 kit: a 3 s `waitForExistence` on a machine running a second
  session and two booted simulators. Treated as environmental, and the reasoning
  is recorded here rather than left as a green tick.
- Timing measured with instrumentation that was then removed; the committed diff
  carries none of it.
- Three UI tests that asserted the literal chart caption now assert
  `hero-battery-level-chart`, because the caption is data-dependent.
- `xcodegen generate` is idempotent against the committed project file.

## Next

Beta notes only, as with 1.9.2 through 1.9.4. Four trains have now gone out with
no store copy pushed; when 1.6.0 clears review there will be a fair amount of
accumulated change to describe.
