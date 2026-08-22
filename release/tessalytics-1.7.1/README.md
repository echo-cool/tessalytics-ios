# Tessalytics 1.7.1 (202608202029)

TestFlight build. 1.6.0 is still `WAITING_FOR_REVIEW` and holds the editable
version record, so this train carries beta notes only.

    ASC_METADATA=release/tessalytics-1.7.1/metadata:app-store/metadata

## What shipped

**1.7.0's live mode never delivered a reading.** The stream connected, reported
itself LIVE, and dropped every event.

`LiveStateStream` decoded `Envelope<StatusDataDTO>` — the TeslaMateApi shape, with
`car` and `status` keys. The backend sends `{"data":{"state":{…}},"meta":{…}}`,
which the request route maps through `BackendStateWrapperDTO`. So every event
failed to decode, `try?` swallowed it, and the loop moved on. Everything on screen
came from the thirty-second poll behind it, which is why pull-to-refresh always
worked and the numbers only moved when something asked for them.

Both routes now share one mapping, `BackendEnvelope.statusData(carID:)`. A test
decodes a real event body and a second asserts the two routes produce the same
status from the same bytes, which is the property that was missing.

Also in this train:

- **The hero map draws the route**, not a pin. `AppEnvironment.liveRoute` fetches
  the drive so far from `/track` once per drive, keyed on the state timestamp, and
  `LiveRoutePath.joined` splices it to the live readings at their closest approach
  to the fetched path's end so the overlap is not drawn twice. Re-fetched on
  reconnect, so an outage does not leave a hole. The camera frames route and car
  in even zoom steps rather than refitting continuously.
- **"updated at 20:25:18"** replaces "updated just now" on the hero. Relative
  wording cannot distinguish a reading a quarter of a second old from one nine
  seconds old, and reads as current right up to the minute mark — including when
  nothing is arriving.
- **Reconnect backoff resets after a working connection.** Six tunnels on one drive
  walked the delay to twenty seconds of stale data; a connection that lasted
  twenty seconds now starts again at one.
- **The stream starts on selection**, not only on a foreground transition. Saving a
  server or switching vehicle left the poll as the only source.
- **Streamed readings are cached every few seconds**, not individually — two SwiftData
  saves per event, five a second, on the main context — with an immediate write
  whenever the state changes and a flush when the stream stops.
- **The live charts and the map route draw thinned series.** Fifteen minutes is over
  two thousand marks, one chart of them a bar per reading, redrawn on every event.
- **The stream pins `min_interval=0.4` and `units=teslamate`.** Both were left to the
  server's defaults; the units default agreeing with the poll's request was luck.

## Verification

- 163 unit tests, 13 UI tests, 1 skipped, plus 5 live-server cases that need a
  `TEST_RUNNER_` prefix to run at all.
- The bug was confirmed against the deployed service, not just in a fixture: an
  event body read from `/v1/vehicles/1/stream` is
  `{"data":{"state":{"vehicle_id":1,…` — the shape 1.7.0 could not decode.
- The transport was cleared as a suspect on both paths. Direct to the container and
  through nginx and the tunnel, state events arrive within milliseconds of the
  broker and keep-alive comments land exactly fifteen seconds apart rather than in
  a batch, so nothing between the app and Postgres is buffering.
- TeslaMate writes positions every 0.34–0.41 s while driving, measured over the
  last five drives, so 0.4 s is the real ceiling on how fresh a reading can be.
- The map was reviewed through `-ui-demo-driving` in light and dark. Demo mode's
  straight-diagonal path gained a gentle curve, tapered to nothing at both ends so
  it still starts and finishes where the snapshots put the car.

## Known gaps

**Not verified on a moving car.** The car was asleep, then offline, throughout;
every measurement above is of the pipeline, not of a drive. The absolute timestamp
on the hero is what makes the remaining check a glance rather than a stopwatch.

The route needs a backend with `/v1/vehicles/{id}/track`; without it the map falls
back to the readings taken since the app opened.

App Store screenshots still do not cover live mode.
