# Tessalytics 1.7.0 (202608201647)

TestFlight build. 1.6.0 is `WAITING_FOR_REVIEW` and holds the editable version
record, so this train carries beta notes only.

    ASC_METADATA=release/tessalytics-1.7.0/metadata:app-store/metadata

## What shipped

Live driving mode, fed by server-sent events.

- **`GET /v1/vehicles/{id}/stream`** on the backend forwards MQTT's push to the
  device. Events coalesce, the database half of the payload is held between
  messages, and a comment goes out on an idle timer so a silent stream is
  distinguishable from a dead one.
- **`LiveStateStream`** in the app reconnects with a backoff on its own; a UI that
  has to re-establish its own connection shows stale values with no sign it
  stopped listening. Streamed and polled state fold into one path.
- **The hero** carries a following map, then speed, power, outside temperature and
  elevation while driving. Below it, distance, top speed, energy net of
  regeneration, consumption, and peak power and regen, with live charts over
  fifteen minutes.
- **Readings are memory-only.** They matter for one journey; thousands of SwiftData
  rows per drive would compete with the history sync to draw a chart discarded at
  the next stop. Energy is integrated with the trapezium rule because TeslaMate
  publishes instantaneous power and no total, and gaps over two minutes are
  skipped — a dropped stream is not a car drawing power throughout.
- **The theme shifts** rather than changes: stronger wash, thicker accent, pulsing
  LIVE badge, same palette.

Also in this train: server rename and removal, the charging curve on one chart
with a thumbnail per row, charger readings gated on the charger actually
delivering, and a sleeping car showing its last known state instead of "Unknown".

## Verification

- 143 unit tests and 13 UI tests. The live-server cases need a `TEST_RUNNER_`
  prefix on the `xcodebuild test` command line or they silently skip.
- Backend: 138 tests, ruff clean, deployed. The app's stream connection was
  confirmed against the live service — `/v1/live` reported `stream_listeners: 1`.
- Live mode itself was reviewed through `-ui-demo-driving`, since a real one needs
  a car that happens to be moving.

## Known gaps

The stream needs a backend with `/v1/vehicles/{id}/stream`; older deployments fall
back to polling. Battery use is higher in live mode by design, and the stream
closes when the app backgrounds.

App Store screenshots do not yet cover live mode.
