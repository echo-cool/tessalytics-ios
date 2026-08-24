# Tessalytics 1.8.9 (202608231725)

TestFlight build. 1.6.0 still holds the editable version record, so this train
carries beta notes only.

    ASC_METADATA=release/tessalytics-1.8.9/metadata:app-store/metadata

## 简体中文

The first language beyond English, with an in-app switch: Settings → Language
offers System, English and 简体中文, and the change lands immediately because the
choice goes into the SwiftUI environment's locale rather than into
`AppleLanguages`, which would need a relaunch to take effect.

**English is the translation key.** The app was retrofitted, not built localized:
hundreds of user-facing strings are plain `String` values handed to custom
components, not `LocalizedStringKey` literals SwiftUI resolves on its own.
Translating by English text means an untranslated string shows in English rather
than as a blank or an identifier — which is what makes adding a language
incremental instead of all-or-nothing. 753 strings are translated.

Two decisions worth recording:

- **Traditional Chinese is not claimed.** `zh-Hant`, `zh-TW`, `zh-HK` and
  `zh-Hant-MO` resolve to English. It is a different script, and serving it
  simplified characters would be worse than serving it English.
- **Data-like values are kept out of the catalogue.** Using English as the key
  means a place named "Home", a car named "Aurora" or an address could be silently
  renamed if it matched an interface string. The defence is the catalogue's
  contents, so that is what `testDataLikeValuesAreNotInTheCatalogue` asserts.

Model code that composes display text has no SwiftUI environment to read, so
`AppText` holds the same choice behind a lock. Two sources for one decision is a
smell, accepted knowingly: the alternative threads a `Locale` through every value
type that happens to produce a sentence.

One defect caught in review: "Recent" and "Nearest" both translated to 最近, which
made two sort orders read identically — worse than leaving both in English. Now
最近去过 and 距离最近, with a test that the destination orders render distinctly.

## The share crash

Reported from a device, with a crash log naming it exactly: `_assertionFailure` →
`EnvironmentValues.subscript.getter` → `ImageRenderer._uiImage` →
`PageSharing.swift:28`.

`SharePoster` stored a *built* view, so the page's content was constructed inside
`share()` — in a `Task`, outside any SwiftUI update. A struct's `@Environment`
wrappers are only valid while the graph is updating that view, so reading one there
traps. The poster now holds a closure and builds during `body`.

The modifier also re-injects `AppEnvironment`, the locale, the colour scheme and
the model context into the rendered poster. `ImageRenderer` builds a detached view
graph that inherits nothing from the screen, so anything a page reads out of the
environment has to be put back or it traps on a missing value — a whole class of
crash rather than the one page that happened to be reported.

## The share slowness

The home screen fetched two `MKMapSnapshotter` images in sequence, each a network
round trip. They now run concurrently, and each is bounded at six seconds:
`MKMapSnapshotter` has no timeout of its own and waits on the network for as long
as the network takes, which is a poor thing to put between a tap and a share sheet.
A poster with a plain panel where the map should be beats one that never arrives.

The timeout is written around the callback API rather than the `async` overload,
because neither `Options` nor `Snapshot` is `Sendable` and so neither can cross the
task boundary a `TaskGroup` race would need.

## Three bugs found by reading a diagnostics export

The export is the one artefact this app produces that a person hands to somebody
else. A real one from a real drive failed at that job three ways.

- **It was not valid JSON.** Coordinate redaction emitted a bare `[REDACTED]`
  token, so `"latitude" : [REDACTED]` broke every recorded event body. Now a quoted
  string — deliberately not `null`, which is indistinguishable from "the car
  reported no position", the one distinction a location log exists to make.
- **The VIN rule was eating numbers.** `\b[A-HJ-NPR-Z0-9]{17}\b` describes
  seventeen digits as well as a VIN, and a `Double` printed in full supplies them:
  304 occurrences of `"age_seconds" : 0.[REDACTED]`. The pattern now requires at
  least one letter, which every real VIN has.
- **Live events evicted the diagnosis.** One shared 400-entry ring, and a stream
  publishing about a reading a second. The export held 394 live events, six
  requests, and not one state change, stream event or failure. Live events now have
  a 300-entry share and spend their own budget.

## Verification

- 525 unit and UI tests passing before the archive.
- `SecretRedactorTests` parses a redacted body as JSON, asserts a redacted
  coordinate is tellable from a missing one, that a seventeen-digit number
  survives, and that a real VIN and real credentials still do not.
- `DiagnosticsCapacityTests` floods twenty minutes of stream readings past three
  diagnostic entries and asserts all three survive.
- `SharePosterConstructionTests` asserts the page is not built until the poster is
  rendered, which is the crash stated as a property.
- `LocalizationTests` covers resolution, fallback, the traditional-Chinese refusal,
  and that data-like values are absent from the catalogue.
- The share sheet was opened on device-equivalent simulator builds and the poster
  confirmed present.

## Known gaps

- **Interpolated strings are still English.** About 93 composed strings — "131 mi ·
  7 days", "updated at 4:20 PM", "mi on the odometer" — build their text at runtime
  and have no fixed key to look up. Mostly numbers with a unit, but "on the
  odometer" and "health" are visibly English on a Chinese home screen. Converting
  them to format strings with positional arguments is a separate pass.
- The share timing was verified on a simulator over a fast network. Whether six
  seconds is the right ceiling on a phone at a charger with one bar is unknown.
