# Tessalytics 1.8.0 (202608220330)

TestFlight build. 1.6.0 still holds the editable version record, so this train
carries beta notes only.

    ASC_METADATA=release/tessalytics-1.8.0/metadata:app-store/metadata

## The map flashed because the card was rebuilt around it

Reported as "the hero map keeps flashing every second, red to black and back".
Reproduced by recording the screen and sampling the mean colour of the map
rectangle per frame: it alternated between the map (R89 G89 B104) and the
red-tinted card behind it (R77 G59 B60 → R61 G49 B51). Screenshots cannot catch
it; the blank frame is a fraction of a second.

The cause was structural, not a rendering bug:

```swift
if isDriving, let coordinate = liveCoordinate { identity; mapButton; details }
else { Button { identity; details } }
```

Two view trees. One reading that arrived without a position — or that simply
failed to mention the gear — swapped between them, and a `Map` that leaves the
view tree is an `MKMapView` torn down. The one built to replace it renders as an
empty surface until its tiles come back, and the card's tint is what showed
through in between.

Three changes, and the rule they share is: **a gap in a reading must not change
the shape of the screen; only a statement may.**

- The hero is one view tree with the map inserted into it.
- `AppEnvironment` holds `liveCoordinate` and `isLiveDriving` rather than
  deriving them per render.
- A drive ends on `isPositivelyNotDriving` — P, asleep, offline, charging — or on
  a five-second grace expiring. Never on a silence.

`-ui-demo-gappy-readings` reproduces the fault on demand (a third of demo
readings carry no position), and `LiveDrivingUITests` holds the map on screen
through eight seconds of it.

## "This drive" was the last eight minutes

`LiveTelemetryBuffer` is a rolling window — fifteen minutes, or 1,200 readings,
whichever comes first. A streaming drive publishes 2.5 readings a second, so the
cap is about eight minutes. Distance, energy, consumption and the peaks were all
derived from it, under labels that said "this drive". A forty-mile motorway run
reported twelve, with nothing on screen saying anything had been dropped.

`LiveDriveTotals` accumulates as readings arrive and is never pruned. The buffer
keeps its window, because a chart of the last few minutes is what a chart of a
drive should be. The card's subtitle now says "So far · 40m" rather than
"Last 8m", which described the charts and the totals with one phrase that was
only true of one of them.

## Where the car actually is

Two bugs, one on each side.

**Backend.** `_LATEST_GEOFENCE_SQL` selected the most recent drive that ended *in
a geofence*, skipping past every drive that ended somewhere unnamed. A car parked
at a friend's house was reported as standing in an address it had left days
earlier. It now takes the most recent drive, full stop, and answers `null` when
that drive ended outside every geofence. A broker that has spoken outranks the
database entirely, so a retracted geofence stays retracted.

**App.** There was nothing to fall back on, so a car with no geofence had no
place at all. `LivePlaceName` reverse-geocodes the coordinate on the device,
throttled to 150 m or 12 s, and asks for the road while moving and the full
address while stopped. A geofence still wins when there is one: "Home" is what
the owner called the place.

## What is steering

`driving.autopilot` on the backend, read from whichever of five name topics and
four flag topics a broker publishes — TeslaMate publishes none of them, so the
field is `null` on most deployments and the badge is simply absent. The
distinction between a `null` block and a block of `null`s is deliberate: a client
has to tell "cannot answer" from "answered, and nothing is steering".

Blue, because that is the colour the car and Tesla's own app use for it.

## Readings that were arriving and going nowhere

The server was sending these and the app was decoding them and discarding them:

- **Tyre pressure warnings** — the car's own judgement, not a threshold this app
  invented. The corner now turns amber with a mark on it, and VoiceOver says so.
- **Occupancy** (`is_user_present`) — the difference between a car parked with
  the family in it and one parked alone with the sentry watching.
- **The cold-weather buffer** — preferred over subtracting the two levels here,
  because the server can compute it from whatever it has.

Plus heading, which was drawn as an arrow on the map and nowhere a driver could
read it quickly.

## Security fixes

- **App Transport Security was never declared.** The project carried
  `INFOPLIST_KEY_NSAppTransportSecurity_NSAllowsArbitraryLoads: NO` for several
  releases; `INFOPLIST_KEY_*` cannot set a dictionary, so the shipped Info.plist
  had no ATS section at all and "Allow local HTTP" could not work on a device.
  Now a real `SupportingFiles/Info.plist` merged into the generated one:
  arbitrary loads off, local networking on. `ServerURLSafetyTests` asserts it is
  in the built bundle, so it cannot silently vanish again.
- **`hasPrefix("10.")` is true of `10.example.com`.** A public hostname shaped
  like a private address was accepted as local, which downgraded the connection
  to cleartext and put the server bearer token on the wire for whoever
  registered it. Hosts are parsed as addresses now. The same fix corrects
  172.16.0.0/12, which was matched as the literal text `172.16.` and so rejected
  every address Docker hands out by default.
- **The diagnostics export leaked coordinates.** The redactor only matched an
  inline `lat, lon` pair; a recorded event body holds them as separate JSON
  fields, so the owner's doorstep survived an export whose own footer promised it
  had been removed. Named coordinate fields are now redacted, with the key kept
  so the shape of the document still reads.
- **Rotated Tesla refresh tokens could be spent twice.** Two requests meeting a
  401 at the same time shared one exchange, but a caller holding a copy from
  before it would then spend a token that was already dead — presenting as "Tesla
  rejected the refresh token" on an account whose credentials were fine.
- **`/v1` named the internal upstream host** in a document served before any
  token was checked. It now reports only whether actions are enabled.

## Also in this train

- The live theme: the wash was `accentBright` at 2.4× normal strength. It is now
  the deeper accent at 1.25×, the night canvas goes *darker* while driving
  (#050506), the card tint dropped from 0.12 to 0.075, and the 4pt red slab
  became a 3pt fading rule.
- Charging rows draw their curve across the full width of the card at 116pt,
  with readable time labels — it was a 138pt column whose axis labels took more
  room than its lines.
- Debug mode, behind five taps on the version number in Settings: live state as
  the app holds it, connection health, an opt-in raw event recorder, and a
  redacted export. Turning it off clears the log and hides the screen.

## Verification

- 236 unit tests, 35 UI tests, 1 skipped.
- Backend: 154 tests, all passing after the remote README merge.
- The flashing map was verified fixed by the same measurement that found it:
  with `-ui-demo-gappy-readings` active, the map rectangle holds one colour for
  the whole recording.

## Known gaps

Not yet verified against a moving car on the real backend. The backend changes
in this train (geofence freshness, `driving.autopilot`) need deploying before the
address fix and the FSD badge do anything on a live server.
