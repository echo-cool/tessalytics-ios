# Tessalytics 1.8.7 (202608231509)

TestFlight build. 1.6.0 still holds the editable version record, so this train
carries beta notes only.

    ASC_METADATA=release/tessalytics-1.8.7/metadata:app-store/metadata

## What one screenshot of a real charge found

1.8.6 shipped the charge forecast having never seen a real one. A single photograph
of the app on a 7 kW wall box exposed three defects, one of them serious.

### The axis began at "now"

The app only holds readings from the moment it is opened, so a car plugged in an
hour earlier produced a session one second old — and a chart that began at the
present, labelled "plugged in 15:01" when the cable had gone in at 13:50.

The start time now comes from the car. The level the charge began at is worked back
from the energy the car reports taking, and that earlier stretch is drawn as a fine
dotted line: it is inferred from two numbers, not watched, and it should not look
like measurement. It is approximate in a known direction — reported energy includes
charging losses the pack never received — which is another reason not to draw it as
a reading.

### The taper was in the wrong place

The serious one. A wall box holds its rate: 7 kW at 64% and 7 kW at 85%. The car
still reports a longer time to full than that flat rate implies, because it eases
off near 100% to balance the pack. 1.8.6 took that difference — correctly
identified as a taper — and spread it linearly across the whole remaining charge.

The result was a forecast putting 80% roughly forty-five minutes later than it
actually arrives, on the screen whose entire purpose is telling somebody when to
come back.

The model now has a knee. Below it the rate is flat; above it the rate decays, and
the decay is fitted so the total still lands on the car's own finishing time.

- **At or above 30 %/h the knee is the current level** — the whole projection bends.
  That rate is 0.3C by definition, which is DC territory: the pack is already at a
  current the chemistry is limiting, and it eases from here.
- **Below that it is a wall box**, the knee is 90%, and everything under it is a
  straight line.

The threshold is expressed as a rate rather than a C-rate on purpose. Percent per
hour *is* a C-rate, read straight off the measurement, so nothing depends on a pack
size that may be wrong or absent.

This remains a two-anchor fit — the rate now, and the car's own time to the limit —
with no charging curve per model baked in anywhere. What changed is the shape the
one free parameter is allowed to take.

### The kilowatt axis was lying slightly

The right-hand ticks came from dividing an arbitrary ceiling into four, so a 7 kW
charge drew against an axis at 2.5 kW intervals whose labels were rounded to whole
numbers for display: 0, 3, 5, 8, 10. Ticks are now chosen from a set of round
numbers.

Also: the "now" rule and the plug-in rule printed their labels on top of each other.
They are at opposite ends of the plot now.

## Verification

- 497 unit and UI tests passing before the archive.
- `testAWallBoxHoldsItsRateAndOnlyEasesOffNearTheTop` pins the defect directly: at
  9.46 %/h with the car predicting 4.7 hours to 100%, 80% must arrive at the flat
  rate rather than forty-five minutes later.
- `testADirectCurrentChargeTapersFromWhereItIsNow` pins that the DC case is
  unchanged, and `testAWallBoxStoppingBelowTheKneeIsAStraightLine` that a charge
  ending at 80% on AC does not bend at all.
- `testTheKneedFitStillLandsOnTheCarsFinishingTime` pins the property the whole
  model exists to preserve.
- A second demo, `-ui-demo-charging-slow`, reproduces the reported situation: a
  7 kW wall box, seventy minutes in, with three minutes of readings. Both demos
  were rendered and looked at.

## Known gaps

- The 90% knee is a judgement, not a measurement. It is roughly where Tesla begins
  balancing on AC, and it only matters for charges that run past it — anything
  stopping at 80% is a straight line either way.
- The inferred opening stretch is drawn as a straight line between two points. The
  charge was not necessarily flat across it, and it is styled to say so.
- The milestone times on a real wall box past 90% are still unverified; that is what
  the beta notes ask testers to watch.
