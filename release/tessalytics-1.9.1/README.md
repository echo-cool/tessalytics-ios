# Tessalytics 1.9.1 (202608232103)

TestFlight build. 1.6.0 still holds the editable version record, so this train
carries beta notes only.

    ASC_METADATA=release/tessalytics-1.9.1/metadata:app-store/metadata

## Why 1.9.1 and not 1.9.0.1

This train was asked for as 1.9.0.1. That was built and offered to Apple, which
refused it:

    code 90060: The value for key CFBundleShortVersionString '1.9.0.1' must be a
    period-separated list of at most three non-negative integers.

Three components is a hard limit of the format, not a convention, so the same
intent ships as 1.9.1. Recorded here because the next person to reach for a
four-part version deserves the answer without spending an archive on it.

## Three layout defects at accessibility text sizes

Found by setting the simulator to accessibility-XL and reading the German and
Japanese screens. Two of the three were invisible to any automated query.

### The parked address collapsed to "1350…"

It shared a row with the gear and state badges under an unconditional
`lineLimit(1)`. The headline directly above it had an accessibility branch; this
line did not. It now takes the width of the card and wraps — where a parked car is
standing is the entire point of that line.

### The odometer icon drew over its own label

`Image().frame(width: 18)` sets a layout width and does not clip, while the glyph
scales with the type size, so `road.lanes` grew straight across "mi auf dem
Kilometerzähler". Scaling the frame does not fix it: the glyph is wider than its
box either way.

The icons now drop out at accessibility sizes, which is what `MetricCard` already
does and for the reason already written there — the label names the figure without
them.

### "Auswertung" was cut to "Auswer…"

The quick links sit four across, so a title gets a quarter of the width. Two lines
at accessibility sizes.

Japanese was clean throughout: it sets taller rather than wider, so nothing ran out
of horizontal room. The tyre diagram's absence at these sizes is deliberate and
unchanged.

## The first test was worthless, which was checked rather than assumed

The address test passed against the *unfixed* code. `firstMatch` on
`vehicle-place` returns the Label's SF Symbol child — an identifier on a `Label` is
inherited by the image inside it — and that child has a fixed height whether the
text wrapped or was truncated.

Querying the static text specifically gives 42.7 points truncated against 130.3
wrapped. The test now fails on the old code and passes on the new, verified by
reverting the fix and running it.

This is the third time in this session that an identifier inherited by a child
element has made a query answer the wrong question. It is worth knowing about.

### What these tests do and do not prove

They verify that controls are present, have a real size, and can be reached. They
cannot see a glyph drawn on top of a label: that defect was invisible to every
query and turned up by looking at the screen. The test file says so in its header,
so a green run is not mistaken for more than it is.

## Verification

- 542 unit and UI tests passing before the archive.
- `AccessibilitySizeUITests` runs German and Japanese at
  `UICTContentSizeCategoryAccessibilityXL` and covers the hero figures, the
  address, the quick links and the language and unit pickers.
- The archive was checked for its version, its six `.lproj` bundles and its
  resources before upload.

## Known gaps

- Only German and Japanese were read at these sizes. French, Simplified and
  Traditional Chinese are covered by the automated checks but nobody has looked at
  them at accessibility sizes.
- Only `accessibilityXL` was exercised, not the two sizes above it.
