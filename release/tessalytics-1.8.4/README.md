# Tessalytics 1.8.4 (202608221645)

TestFlight build. 1.6.0 still holds the editable version record, so this train
carries beta notes only.

    ASC_METADATA=release/tessalytics-1.8.4/metadata:app-store/metadata

## The pack a car was built with, from its VIN

"Capacity when new" is the denominator of every health estimate in the app, and
until now there were two ways to get it: derive it from recorded history, which
understates any car whose logging began after the pack had aged, or have the owner
know the figure and type it in.

A Tesla VIN names the model (position 4), the model year (position 10) and the
factory (the WMI and position 11, which corroborate each other). A table shipped
in the app turns those into the pack.

**Keyed on the factory, not the market.** This is the part that is easy to get
wrong: a 2021 Long Range AWD Model 3 is 82 kWh of Panasonic cells from Fremont and
79 kWh of LG cells from Shanghai, and both were sold in Europe. The VIN names the
factory, so the factory is the key.

Three deliberate refusals, all for the same reason — this figure rewrites every
degradation number on every screen:

- **A VIN that fails its own check digit is rejected**, as is one whose WMI and
  plant code name different factories. Either is a typo or a misread, and the
  honest answer to both is "I cannot tell you".
- **The variant is not read from the VIN.** It is not reliably encoded there, so
  it is a picker, pre-filled from TeslaMate's trim badge only where that is
  unambiguous. Guessing Performance for a Long Range is wrong by three
  kilowatt-hours.
- **The chemistry is not read either.** Published decoders disagree about what
  position 7 means — sources claim both `E`/`F` and `G`/`N`/`P` — and a field
  nobody agrees on is not one to read when this is what it feeds.

Where a model year spans a supplier change, both packs are offered and the owner
picks: a 2023 Berlin Model Y Standard was built with 60 kWh of BYD cells and
62 kWh of CATL, and choosing for them would be a coin flip that rewrites their
history. Nothing is applied silently — tapping fills the field, and an owner's own
figure always wins.

### Why the table ships in the app

Not on a server, and not on a Tessalytics-operated host. The app talks to any
TeslaMate backend, including TeslaMateApi, so a table held by one of them would
leave everyone else without it. Health is computed offline, so a number that needs
the network disappears in a garage. And fetching it from a host of ours would
contradict the "no Tessalytics cloud" promise in the README, PRIVACY.md and the
App Store listing — a static file still reveals every user's IP.

If it ever needs updating without an app release, the honest route is the owner's
own backend, which is a server they already chose to trust.

## Also fixed

- **An achievement's requirement was in kilometres above its progress in miles** —
  "Complete a single drive of 300 km" over "96 of 186 mi", which reads as two
  different targets. Caught from a screenshot of the real app.
- **Debug mode wanted five taps inside three seconds, measured from the first.**
  Settings has grown since that was written, and on a slower device a real person
  can exceed it mid-run with nothing on screen explaining the reset. Five seconds
  now, measured between consecutive taps. This was a failing UI test in 1.8.3; it
  turned out to be failing for a real reason.
- **`WebPairingUITests` was failing as a cascade** from the above, not on its own
  merits. Fixing one fixed both.

## Going public

The three repositories are open source, so this train also carries what that
needed: the README leads with the TestFlight link and a gallery that resolves —
the old one pointed at `.jpg` files that were never there — the TeslaMate
trademark notice is spelled out in all three READMEs, and the About screen links
to all three repositories.

## Verification

- 279 unit tests, 47 UI tests, 1 skipped, all passing before the archive.
- `VINDecoderTests` builds its fixtures with a computed check digit, so a fixture
  cannot drift out of agreement with the validator it exercises.
- `BatteryPackCatalogueTests` loads the **shipped** resource rather than a
  fixture, so a table that fails to parse fails the suite.
- The archive was checked for its version, its ATS policy and for
  `battery-packs.json` actually being in the bundle before upload.

## Known gaps

- The twelve Game Center achievement identifiers still do not exist in App Store
  Connect. The app's own achievements screen works regardless and shows the
  refusal verbatim — "this application is not recognized by Game Center".
- The pack table covers Model 3, Model Y and Cybertruck for Fremont, Austin,
  Shanghai and Berlin, 2019–2025. A Model S or X returns no match and falls back
  to the derived figure, which is the pre-existing behaviour.
- Direct Tesla's 412 fix is still verified against a mock rather than a live
  account.
