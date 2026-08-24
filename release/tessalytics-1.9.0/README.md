# Tessalytics 1.9.0 (202608231816)

TestFlight build. 1.6.0 still holds the editable version record, so this train
carries beta notes only.

    ASC_METADATA=release/tessalytics-1.9.0/metadata:app-store/metadata

## Five more languages

English, Deutsch, Français, 日本語, 简体中文 and 繁體中文 — 813 keys each, chosen in
Settings and applied without a relaunch.

**Traditional Chinese has its own catalogue**, not a rendering of the simplified
one. The two differ in vocabulary as well as script — 軟體 rather than 软件, 網路
rather than 网络, 資料 rather than 数据 — and it was produced with OpenCC's `s2twp`
conversion, which handles both, plus a small overlay for terms it leaves alone
(令牌 → 權杖, 演示 → 示範).

The translations are mine and have not been reviewed by native speakers. That is
recorded in the README and the beta notes rather than left for someone to discover.

Adding a language is now one `.lproj` file and one case in `AppLanguage`.

## Units are a choice, and the choice converts

Settings → Units offers **From the car** (the default), **Metric** and **Imperial**.

The important part: values arrive from TeslaMate already converted into the car's
units, so a preference has to convert them. Relabelling would put "bar" under a psi
number, which is worse than showing the wrong unit honestly because it looks like an
answer.

`UnitsDTO` now carries the preference alongside the server's symbols — excluded from
its `Codable` keys, because it is this app's opinion and not part of the payload —
and exposes both the source symbols and the display ones. `ValueFormatting` converts
before it formats.

Energy per unit distance inverts: 150 Wh/km is 241 Wh/mi, not 93. Getting that the
usual way round would report a car as far more efficient than it is, so it has its
own test.

### Three call sites bypassed the conversion, and a screenshot found them

Formatting a raw value beside `units.pressureSymbol` skips the conversion entirely.
Running the app in Japanese with metric selected showed:

- **range 238.00 labelled km** — 238 is miles; it should read 383.02
- **odometer 18,642.0 labelled km** — should read 30,001.4
- **tyres 42.1 labelled bar** — a psi reading wearing bar's name

All three formatted the number themselves rather than going through
`ValueFormatting`. `UnitConversionReachesTheScreenTests` now asserts the hero's range
converts, which is the shape of bug that the unit tests on `UnitsDTO` could not have
caught: the conversion was right, and nothing called it.

## The words that were still English

About fifty phrases composed their text at runtime — "131 mi · 7 days", "updated at
5:58 PM", "mi on the odometer" — so there was no fixed key to look up and they stayed
English on a translated screen. They are now format strings with positional
arguments, which also lets a language reorder the values and the words around them.

`Locale.appFormat` and `AppText.format` are the two entry points; a test asserts that
every translation in every catalogue keeps exactly the placeholders its key has,
because a dropped or reordered `%@` prints the wrong value or crashes.

Left English deliberately: bare units (kWh, Wh/km), version strings, and the owner's
own place and vehicle names.

## Verification

- 520-odd unit and UI tests passing before the archive.
- `UnitPreferenceTests` covers both directions, the inverted efficiency factor,
  round-tripping, and that the preference never appears in an encoded payload.
- `LocalizationTests` now checks all six catalogues resolve, that Traditional
  Chinese differs from Simplified, and the placeholder-integrity sweep across every
  language.
- German, French and Japanese were each run in the simulator and read on screen;
  that is how the conversion bypasses and the truncated German label were found.

## Known gaps

- **No native speaker has reviewed any of this.** The Chinese I am most confident
  in; German, French and Japanese are good but unreviewed. The beta notes ask
  testers for corrections by screen.
- A handful of composed strings remain English — mostly a number with a bare unit,
  where there is nothing to translate.
- Layout was checked at default type size in three languages. Longer German strings
  at accessibility sizes are unverified.
