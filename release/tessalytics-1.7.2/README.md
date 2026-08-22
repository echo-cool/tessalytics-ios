# Tessalytics 1.7.2 (202608202158)

TestFlight build. 1.6.0 still holds the editable version record, so this train
carries beta notes only.

    ASC_METADATA=release/tessalytics-1.7.2/metadata:app-store/metadata

## The stream never delivered a reading

```swift
for try await line in bytes.lines { if line.isEmpty { /* emit */ } }
```

`AsyncLineSequence` does not report empty lines. A server-sent event ends with a
blank line. So the terminator never arrived, the framing accumulated forever, and
every reading was discarded — with the connection up and the badge lit. Proven
directly: feeding `"a\n\nb\n\n"` through `.lines` yields two lines and no blank.

This survived 1.7.0 and 1.7.1 because the tests all took lines as their input, and
the defect was in what produced them. It also masked the envelope mismatch fixed
in 1.7.1: both bugs sat on the same dead path, which is why fixing one changed
nothing observable.

The stream now splits bytes itself (`EventFraming.consume(byte:)`), handles CRLF,
and is covered by a loopback server (`FakeEventStreamServer`) that serves the same
bytes the backend does. Against the old read loop those tests report zero readings.

Evidence from the drive that prompted this, from the deployed backend's log: one
`GET /v1/vehicles/1/stream` at 04:12:03Z, open and silent for the whole journey,
with `/state` polls every 30.5s beside it — the poll was the only thing moving the
screen.

## Also fixed

- **The route on the hero froze** where the app joined the drive: the only thing
  extending it was the readings being dropped. The buffer is now fed by the poll
  as well, and the drive's path is re-read from `/track` every 90s, so it cannot
  drift out of date whatever the stream is doing.
- **`.inactive` was treated as backgrounded.** A notification banner or the screen
  dimming tore the stream down and rebuilt it — fifteen reconnects in half an hour
  in the log. Only `.background` closes it now.
- **The capacity detail screen** drew a different chart from the card that opened
  it. The explorer grew a points style, a trend series placed in the plotted
  points' index space, and a reference line, so both draw the scatter, the median
  and the as-new line.
- **Charts on drives and charging sessions are tappable**, through one shared
  `ExplorableChart.timeSeries` builder, so both screens behave alike.
- **Charging rows carry axes**: percent left, kilowatts right, the session's span
  underneath, both series named — and the row's spoken value says the same.
- **The Activity list was decoding a whole drive per row on the main thread**, then
  redoing it on every recycle. `HistoryPreviews` caches per id and the decode and
  the Douglas-Peucker run off the main actor.
- **Sparse history is explained rather than blank.** `ChartNeedsMoreHistory` and
  `HistoryCoverage` say what a chart is waiting for and that the fix is time.
- **The home screen is titled with the app's name**, not the car's.

## Verification

- 190 unit tests, 20 UI tests, 1 skipped, plus 5 live-server cases that need a
  `TEST_RUNNER_` prefix to run at all.
- Backend: 145 tests (`tests/test_stream.py` now asserts the wire format — that an
  event ends with a blank line, that the body is one line of JSON, that a
  keep-alive carries no data), ruff clean.
- The transport was cleared on both paths, with and without compression requested:
  events arrive within milliseconds and keep-alives land exactly 15s apart.

## Known gaps

**Not yet verified on a moving car.** Every measurement here is of the pipeline and
of the app against a fake server. The absolute timestamp on the hero is what makes
the real check a glance.
