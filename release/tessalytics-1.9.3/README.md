# Tessalytics 1.9.3 (202608242300)

TestFlight build. 1.6.0 still holds the editable version record
(`WAITING_FOR_REVIEW`), so this train carries beta notes only — there is still
nowhere for store copy to land until that submission clears.

    ASC_METADATA=release/tessalytics-1.9.3/metadata:app-store/metadata

Uploaded 2026-08-24 23:0x from `main` at `dce73bf`, archived Release,
`destination: upload`. The `metadata/` directory here holds beta notes only:
`version.txt`, `build.txt` and `testflight_whats_new.txt`. Nothing in the store
copy changed, and `scripts/asc.py` skips any field whose file is absent rather
than overwriting a good description with a stale one.

## What changed since 1.9.2

### "Not set" could be tapped but never took

On Vehicle rating, choosing "Not set" for the pack variant always snapped back
to whatever the trim badge suggested. A cleared variant was written as `nil`,
and `nil` already meant "the owner has not said" — which is precisely what
licenses the guess from the trim. An explicit clear now stores a sentinel.

Two more defects surfaced beside it, both of which would read the same way on
screen. `savePackVariant` returned early and saved nothing for a car cached in
memory but never written to the store. And a stored variant that the model's
list does not offer — a Cyberbeast on a Model Y — left the picker with no row to
mark, which looks exactly like a control ignoring every tap.

### TeslaMate's Grafana set is now covered

The dashboard list in `teslamate-org/teslamate` was checked rather than
remembered. Twelve were already answered here. Five were not, and now are:

- **Efficiency** (new Analysis section) — `efficiency`. Consumption against
  outside temperature in fixed bands, weighted by distance so a two-mile trip
  from cold does not count the same as a hundred-mile run; consumption by month;
  consumption against trip length.
- **Mileage** (new Analysis section) — `mileage`, `statistics` and `states`. The
  odometer curve on a focused scale, distance and charging by month, and the
  driving / charging / parked split of the period.
- **Standby drain** on the battery page — `vampire-drain`. One point per parked
  stretch of six hours or more, sized by duration, against a rule at the median
  daily loss. Stretches where the level *rose* are dropped: the car was charged
  somewhere TeslaMate did not see, and counting that as negative drain would
  flatter the average.

`database-info` is server health with no client equivalent and `reports/dutch-tax`
is single-jurisdiction; neither was ported. `timeline` is answered by the
Activity tab beside the home screen's battery trace.

### Metric grids fill their rows

Four cards in an adaptive grid fills two of three columns on the last row and
leaves the rest blank. Every grid carries six now — six works at two columns and
at three, four only at two.

### A demo fixture that was quietly wrong

Filling the battery grid exposed it. `DemoExperience` generated each event's
battery level from its own id, so a drive could end at 70% and the charge an
hour later begin at 26%. Nothing read the gap between two events until standby
drain did, and it reported 20%/day. Demo levels now walk a single ledger across
the whole history; the panel reads 1.5%/day.

### Less text

About ninety strings are shorter or gone. More to the point, roughly forty
on-screen *elements* went with them: ten single-series chart legends that
restated the card title in smaller type, twelve x-axis titles under axes whose
ticks already read "Aug 16", twelve subtitles repeating their own heading, two
Settings footers whose section header had already said it, and one onboarding
row that made the same point as the row above it.

`tessalyticsChartAxes` now draws nothing for an empty title, so a blanked axis
reclaims the space instead of leaving a gap. The value labels inside `Chart` are
untouched, so VoiceOver and the Audio Graph read what they read before.

English text is the localization key, so all six catalogues moved: 78 strings
removed or rewritten, 735 untouched, 123 added — the net is 1,359 fewer
characters *while* gaining the new dashboards' labels.

## Verification

- 482 unit tests and 71 UI tests, 0 failures, on the archived tree.
- `WebPairingUITests` failed twice in one full run and passed in isolation and in
  the run that followed. A contended-simulator flake, not a regression — the
  screen it guards was touched only by a string change this train.
- `xcodegen generate` is idempotent against the committed project file.
- Archive reports `CFBundleShortVersionString 1.9.3` /
  `CFBundleVersion 202608242300`; `manageAppVersionAndBuildNumber` is `false` in
  the export options so Xcode cannot substitute its own number on the way out.
- `ITSAppUsesNonExemptEncryption` is `false` in the built app.

## Next

Beta notes only, as with 1.9.2. When 1.6.0 clears review the editable record
frees up and the store copy in `app-store/metadata` can be pushed against
whichever train is current — see `scripts/asc.py prepare-version` and the note in
the 1.2.1 kit about withdrawing before preparing a new one.

The Supabase account and config sync is still not here; it remains on
`feature/supabase-account-sync` waiting on the same three non-code items listed
in the 1.9.2 kit.
