# Tessalytics 1.8.2 (202608221420)

TestFlight build. 1.6.0 still holds the editable version record, so this train
carries beta notes only. Everything in
[1.8.1](../tessalytics-1.8.1/README.md) is in this build; this kit is the one
change on top of it.

    ASC_METADATA=release/tessalytics-1.8.2/metadata:app-store/metadata

## The hero card kept showing a home address

Reported directly: "the address on the hero card keeps showing my home address" —
and, on the follow-up, **in live mode**: for the whole of a drive, under the word
"Driving", the card named the owner's house.

1.8.0 fixed the server half of this — the backend's `/state` no longer walks back
to the last drive that ended in *any* geofence — and 1.8.1 added on-device
geocoding as a fallback. Neither was enough, for the same reason: the app still
preferred the server's geofence when there was one.

TeslaMate names a place only when a **drive** ended inside a geofence the owner
had drawn. That is a fact about a completed journey, not about where the car is,
and for a car that parks anywhere else the answer is simply the last named place
it ever visited. Correct data, answering a different question — which is the worst
kind of wrong, because it looks right.

So the geofence is not consulted for this at all now. `VehicleHeroSummary` takes
the place name from `LivePlaceName` and from nothing else: a MapKit reverse
geocode of the coordinate the server reports, asking for the road while the car
is moving and the full address while it is stopped, throttled to 150 m or 12 s.

### A parked car reports no position at all

The second half of the report: when parked, use the last known location.

A Tesla goes to sleep, and a sleeping car publishes nothing — no position, no
tyre pressures, no lock state. Resolving only the newest reading therefore left
the line blank for the state a car spends most of its life in.
`placeCoordinate(for:)` falls back to the position on `lastLiveStatus`, the last
reading taken while the car was awake. It has not moved since, so that reading is
still where it is — the same rule the tyre diagram has always used.

Mid-drive the fallback is different and deliberately so: a driving reading without
a position falls back to the latched `liveCoordinate`, not to the last parked one.
A gap in the stream must not send the car home.

When nothing resolves at all — no position ever recorded, no network, a geocoder
that declines — the line is **hidden**. Not "Location unavailable", not the last
thing it knew: absent. A line that is sometimes a guess is a line that can never
be trusted. `0,0` is not a fallback either; a server with no reading publishes it,
and naming it would put the car in the Gulf of Guinea.

The same change applies to the Location row under "Software & details", which was
reading the same geofence.

`VehicleHeroSummary.locationText` is gone with it. Nothing displayed it — only a
test still referenced it — and keeping a second, differently-worded copy of this
answer around was how the two could have drifted apart.

## Also here

- The parked demo now carries a coordinate and no geofence, so the demo exercises
  the geocoding path rather than the one that was just removed. The dashboard
  smoke test asserts the geocoded address is shown and that "Home" is not.

## Verification

- 265 unit tests, 44 UI tests, 1 skipped, all passing.
- `VehicleHeroSummaryTests.testTheServersGeofenceIsIgnoredEntirely` pins the rule:
  a summary given both a geofence and a resolved address shows the address.
- `testWithNothingResolvedThereIsNoPlaceToShow` pins the other half: with a
  geofence and no resolved address, there is no place text at all.
- `LivePlaceResolutionTests` drives the environment with a geocoder it can
  observe, and checks which coordinate the app chose to name: a driving car's own
  position over a geofence, a sleeping car's last known position, a gap mid-drive
  staying on the road rather than falling back to the driveway, and `0,0` naming
  nothing.

## Known gaps

Reverse geocoding needs a network. A car parked in a garage with the phone offline
shows no address rather than a stale one, which is the intended trade and worth
knowing about.
