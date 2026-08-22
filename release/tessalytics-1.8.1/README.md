# Tessalytics 1.8.1 (202608221400)

TestFlight build. 1.6.0 still holds the editable version record, so this train
carries beta notes only.

    ASC_METADATA=release/tessalytics-1.8.1/metadata:app-store/metadata

## Direct Tesla failed at its very first request

Reported as "HTTP 412". `GET /api/1/vehicles` on the Owner API has answered
**412 Precondition Failed** since Tesla changed it in January 2023 and never
brought it back, so `configure()` failed before it had done anything — and the
app reported it as merely "an unexpected response", which is how a permanent and
well-documented breakage reads as a mysterious one.

The account's cars now come from `/api/1/products`, which still answers and
carries the same fields for a car: `id`, `vehicle_id`, `vin`, `display_name`,
`state`. That list is heterogeneous — an owner with a Powerwall or solar gets
those back too — and a VIN is what separates a car from a battery on a wall.
412 also has a case of its own now, because reporting a status nobody can act on
as a surprise helps no one.

### One field, not two

Connecting asks for the **refresh token** alone. The access token is derived from
it by definition, expires in hours where the refresh token lasts months, and the
app already knew how to mint one — asking for both only created a way for the
pair to disagree, so a stale access token beside a perfectly good refresh token
failed instead of being replaced. A connection that mints a token but then cannot
list the cars stores nothing: a credential the owner cannot use is worse than
none.

## The hero card led everywhere and nowhere

Every figure on it opened battery health, including the tyre diagram. Each one
now leads to the screen it is about:

| Tap | Opens |
| --- | --- |
| Battery ring, range, health % | Battery health |
| Odometer, the week's driving, consumption | Drive history |
| The tyre diagram | Tyres — each corner, with the car's own warnings |
| The car's name | Vehicle settings, which holds the rating when new |
| The map | The full-screen map, as before |

Structurally this meant removing the outer buttons rather than adding inner ones.
A control inside another control is unreliable to tap and invisible to VoiceOver,
which collapses a button's children into a single element — so the card is no
longer a button at all, and each figure is its own.

`TyrePressureView` and `VehicleSettingsView` are new. Vehicle settings carries the
identity, the rating editor that already existed but was buried in Settings, the
software history, the vehicle picker when there is more than one car, and what the
server holds for it.

## Software history is a timeline, not a list of dates

TeslaMate records the moment a version was *installed*. What an owner wants is the
other thing — how long the car then ran it, and which version it was on some day
they remember — and that is the gap between one install and the next, which was
derivable and never derived.

`SoftwareTimeline` turns installs into periods. The screen draws a bar per version
across the months it ran, and each row says how many days the car spent on it. Two
installs on one day report "Under a day" rather than rounding up to one, because a
version the car ran for twenty minutes should not look like a day's use.

## Achievements

Twelve, all facts about the car and all computed on the device from synced
history: distance, a drive in one sitting, energy through the pack, consecutive
days driven, night drives, places visited, versions run, pack health held past
50,000 km. Nothing rewards *opening the app*, which would be a reason to open it
rather than a fact about the car.

Two deliberate constraints:

- **Targets are held in kilometres** whatever the display units. A target that
  moved when an owner switched to miles would not be a target.
- **Game Center is where they are recorded, not where they come from.** The list
  works signed out, in a region without Game Center, and before the identifiers
  exist in App Store Connect. Progress is reported only when it has actually
  moved — the figures are recomputed on every history sync, and re-sending an
  unchanged 40% each time buys nothing.

The `com.apple.developer.game-center` entitlement is now in the app and signed
into the archive.

**Still to do outside this repo:** the twelve achievement identifiers have to be
created in App Store Connect before Game Center will accept a report. Until then
`GKAchievement.report` fails with "achievement does not exist", which the app
records on the achievements screen and otherwise ignores. The identifiers are in
`AchievementCatalogue`, all prefixed `com.echocool.Tessalytics.achievement.`.

## Smaller things

- **Range shows two decimals, the odometer one.** Rounded to whole units, a range
  that was visibly falling looked like one that was stuck, and a short errand
  moved nothing on screen.
- **The gear is shown.** P, D, R or N, beside the state. The app read `shift_state`
  on every reading and displayed it nowhere.
- **The demo's newest software install is three weeks old** rather than this
  instant, so the current version has a bar on the timeline rather than a
  zero-width one.

## Verification

- 258 unit tests, 44 UI tests, 1 skipped, all passing.
- `HeroNavigationUITests` covers each of the six destinations, the gear badge, the
  timeline and the achievements list.
- `OwnerAPIConnectionTests` covers the products endpoint, energy hardware being
  filtered out, 412 reported as itself, refresh-token-only connection, and both
  failure paths storing nothing.
- The Game Center entitlement was confirmed in the signed archive with
  `codesign -d --entitlements`.

## Known gaps

Direct Tesla is fixed against the documented behaviour of an undocumented API and
tested against a mock; it has not been exercised against a real Tesla account from
this machine. The 412 was reproducible from the report alone, and the endpoint
change is well established, but the first real confirmation will be yours.
