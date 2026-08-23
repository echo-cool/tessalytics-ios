# Tessalytics 1.8.5 (202608231311)

TestFlight build. 1.6.0 still holds the editable version record, so this train
carries beta notes only.

    ASC_METADATA=release/tessalytics-1.8.5/metadata:app-store/metadata

## Send a place to the car

The car has already been everywhere the owner goes, and Tessalytics recorded those
arrivals. The home screen now offers them back as one tap each: ordered by visits, by
recency, or by distance from where the car is standing, filterable, capped at ten, and
hidden while the car is driving.

**It goes through the share sheet, not through an API.** Tap a place and iOS opens the
share sheet with a map link; the owner picks Tesla, whose share extension forwards the
destination to the car. That needs no Tesla account, no token and nothing to connect —
which is the point.

Three decisions worth recording:

- **The link carries the coordinate, not the name.** The car re-geocodes whatever it is
  handed, so "Home" or "Whole Foods Market" resolves to whichever one the car's own
  search prefers rather than the one the car has actually been parking at.
- **TeslaMate is not an alternative route.** It is a logger: it reads the car and writes
  rows, and neither it nor TeslaMateApi has any endpoint that sends a command to a
  vehicle. The Tessalytics backend holds no Tesla token by design, so it has nothing to
  send one with either. This was worth checking rather than assuming.
- **"Nearest" with nowhere to measure from falls back to most-visited.** A car that has
  never reported a position has no nearest, and an arbitrary order under that heading
  would be a lie.

## Share a page as one picture

Eleven screens carry a share button in the top right. What it produces is the whole
page as a single tall image — not a screenshot of whatever happened to be scrolled into
view, and not a line of text. The page is laid out again at a fixed 420pt width and
drawn at 3× in one piece, with the figures summarised above it, a Tessalytics mark in
the bottom right, and a written summary travelling alongside so a message thread quotes
real numbers.

Two things `ImageRenderer` cannot do, handled rather than shipped broken:

- **It cannot draw a `Map`.** MapKit renders through UIKit and the renderer only walks
  SwiftUI's own layers, so a map in a poster comes out blank. `RoutePosterSnapshot`
  fetches the tiles through `MKMapSnapshotter` and draws the route and pins itself —
  on the tap, not on page load, so a page nobody shares downloads nothing.
- **It cannot draw a `List`.** A `UICollectionView` underneath renders empty, so the two
  history screens rebuild their rows as a plain stack for the poster, capped at twenty
  with the remainder counted.

An environment value, `isRenderingSharePoster`, lets a view know which it is being drawn
for. Controls are left out on that basis: the analytics period picker, the Game Center
sign-in card and the charging map are widgets, not facts, and a picture of them says
nothing.

## Direct Tesla is developer-only

The Owner API now lives behind the debug unlock — five taps on the version number —
rather than being offered in Settings and on the home screen.

It is unofficial, undocumented, and Tesla retires parts of it without notice:
`/api/1/vehicles` has answered `412 Precondition Failed` since January 2023 and never
came back. Offering it as a feature invites owners to depend on something that can stop
working under them between one Tesla deploy and the next. Nothing that reads from
TeslaMate is affected, stored tokens are untouched, and the screen is exactly where it
was for anyone who unlocks it.

The demo was made consistent with this: it no longer simulates a connected Tesla account
unless debug mode is on, because it was claiming "Direct live" on a screen with no direct
controls anywhere on it.

## Verification

- 452 unit and UI tests passing before the archive, including 24 new ones.
- `DestinationShortlistTests` pins each ordering, the tie-break, the filter, the cap, and
  the nearest-without-an-origin fallback.
- `CarDestinationLinkTests` pins the link format including southern and western signs.
- `OwnerAPIClientTests` pins the share command's shape — `share_ext_content_raw`, the
  nested intent value, locale and timestamp — and that a refusal surfaces rather than
  reading as a success.
- `PageSharingTests` proves the poster is fixed-width, grows past any phone's height,
  is 3× and opaque; `RoutePosterSnapshotTests` covers the region maths.
- The route drawing and the poster chrome were both rendered to disk and looked at, not
  merely asserted about.
- Two existing dashboard tests failed honestly against the new card — it puts the word
  "Home" on screen and pushes the driving chart out of the lazy stack's realized range.
  The geofence assertion was scoped to the hero card and the chart given a scrolling
  check, rather than either being weakened.

## Known gaps

- **The Owner API `share` command has never been sent to a real car.** It is built to the
  documented shape and tested against a mock. It is only reachable behind the debug
  unlock, and the path every owner takes — the share sheet — does not use it.
- The Tesla app's share extension accepting the link is likewise unverified from here;
  it is the first thing to check on a real phone.
- The twelve Game Center achievement identifiers now exist in App Store Connect but have
  not been exercised against a signed-in account on a device.
