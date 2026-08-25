# Tessalytics 1.9.4 (202608242357)

TestFlight build. 1.6.0 still holds the editable version record
(`WAITING_FOR_REVIEW`), so this train carries beta notes only.

    ASC_METADATA=release/tessalytics-1.9.4/metadata:app-store/metadata

Archived Release from `main`, `destination: upload`. The `metadata/` directory
holds beta notes only — nothing in the store copy changed, and `scripts/asc.py`
skips any field whose file is absent rather than overwriting a good description
with a stale one.

## What changed since 1.9.3

One fix: the share button on the home screen sat spinning.

### It was the map, not the drawing

Measured rather than guessed. On the home screen, instrumented end to end:

| stage | time |
| --- | --- |
| `prepare()` — `MKMapSnapshotter` tile fetch | 0.92 s |
| `ImageRenderer` — draw the poster | 0.05 s |
| `LPLinkMetadata` | 0.00 s |
| `pngData()` on picking a target | 0.04 s |

So the poster was never expensive. Two things turned that 0.92 s into the wait
that got reported.

**The wait was unbounded from the owner's side.** `snapshot(with:timeout:)` gave
the fetch a six-second ceiling, but `prepare()` awaited all of it — so a slow or
unreachable tile server left the button spinning for six seconds.

**The cache almost always missed.** It keyed on exact coordinate equality, and a
parked car's reported position wanders by centimetres between readings. A map
that had not moved was refetched on every share; a moving car refetched by
design, which is correct but should never have blocked.

### The fix

The wait is now bounded separately from the fetch. `load` waits
`RoutePosterSnapshot.budget` — 1.5 s — and returns. The fetch it started carries
on and writes into the cache, which is what makes the tap after a slow one
instant rather than slow again. Beside that: the key rounds coordinates to about
a metre; a failed fetch leaves the last good map in place rather than blanking
it; and two callers for one map park on a single request.

### A no-op that read like a fix

Worth recording, because it nearly shipped. The first attempt raced the fetch
against the budget with a `TaskGroup` and `cancelAll()`. It did nothing at all —
0.927 s measured against a 50 ms budget. `await task.value` on a
`Task<_, Never>` ignores cancellation of whoever is awaiting it, so the group
waited out the whole fetch and the budget was decoration. The working version is
a continuation resumed by whichever of the fetch and its deadline arrives first.

The lesson is narrow and worth keeping: after changing something for
performance, measure it again. This one compiled, read correctly, and changed
nothing.

## Verification

- 482 unit tests and 71 UI tests, 0 failures, on the archived tree.
- Timing verified with the budget forced to 50 ms: first share `prepare=0.054 s`
  and no map, second share `prepare=0.001 s` with the map present, recovered
  from the fetch the first share abandoned. At the shipped 1.5 s the normal
  0.92 s case still includes the map.
- The share buttons on a drive, the places map and the analysis screens use the
  same `RoutePosterSnapshot`, and were exercised by hand.
- All timing instrumentation removed; the committed diff is
  `RoutePosterMap.swift` only.
- `xcodegen generate` is idempotent against the committed project file.

## Known judgement call

1.5 s was chosen against simulator numbers, where the fetch takes about 0.9 s. On
a materially slower connection the *first* share of a session will come out
without its map, and the second will have it. The beta notes ask testers whether
that is happening, because the alternative — prefetching tiles when the screen
appears — spends network on everyone who never shares, which the original design
deliberately avoided.

## Next

Beta notes only, as with 1.9.2 and 1.9.3. When 1.6.0 clears review the editable
record frees up and the store copy in `app-store/metadata` can be pushed against
whichever train is current.
