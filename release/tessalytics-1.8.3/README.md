# Tessalytics 1.8.3 (202608221500)

TestFlight build. 1.6.0 still holds the editable version record, so this train
carries beta notes only.

    ASC_METADATA=release/tessalytics-1.8.3/metadata:app-store/metadata

This train is [1.8.1](../tessalytics-1.8.1/README.md) and
[1.8.2](../tessalytics-1.8.2/README.md) with the in-progress web-pairing work
alongside it. Nothing in the app changed between 1.8.2 and this build except that
pairing feature, which is why there is no separate list of fixes here — read those
two kits.

## Why this build exists

1.8.2 was archived at 14:41 and two more pairing files changed after it, so the
build on TestFlight was already behind the tree. Rather than leave a train that
matched neither the last kit nor the working tree, this one is cut from the tree
as it stands.

## Web pairing is included and is not finished

The browser-pairing feature — `WebPairing`, `BackendPairingAPI`, the QR scanner,
the pairing sheet and the paired-browsers screen — was authored separately and is
still in progress. It is in this build because it is in the working tree, and the
beta notes say so plainly.

Worth recording, because it was not obvious at the time: **1.8.2 also shipped it.**
Those files landed in the tree at 14:23–14:31, between the 1.8.1 archive (14:01)
and the 1.8.2 archive (14:41), and the 1.8.2 binary carries thirteen pairing
symbols where 1.8.1 carries none. It compiled and its tests passed, so nothing was
broken by it — but a build went to testers carrying a feature nobody had decided
to ship. Checking `git status` before archiving is the cheap habit that would have
caught it.

## Verification

- Full suite green on the combined tree: the app's own tests plus `WebPairingTests`
  and `WebPairingUITests`.
- The archive was checked for its version, build number and App Transport Security
  policy before upload, as with every train in this series.

## Known gaps

- Web pairing is unfinished by its author's own account; treat its behaviour as
  provisional.
- The twelve Game Center achievement identifiers still have to be created in App
  Store Connect before Game Center will accept a report. The in-app achievements
  list does not depend on it.
- Direct Tesla's fix is verified against a mock and the documented behaviour of an
  undocumented API, not yet against a real Tesla account from this machine.
