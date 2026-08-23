# Tessalytics 1.8.8 (202608231544)

TestFlight build. 1.6.0 still holds the editable version record, so this train
carries beta notes only.

    ASC_METADATA=release/tessalytics-1.8.8/metadata:app-store/metadata

## The forecast stops assuming and starts measuring

Two changes, both from the same observation: the app was modelling a taper it had
no evidence for, in cases where there was either no taper at all or a real one it
could have gone and looked at.

### Below 10 kW nothing tapers

A wall box is the charger's limit, not the pack's. Ten kilowatts into any Tesla
pack is under 0.15C — nothing about the chemistry is being asked for at that
current — so the rate holds for the whole session, the power line is level, and the
forecast is a straight line.

1.8.7 still bent it above 90%, on the reasoning that the car's longer estimate must
be the balancing it does near the top. That reasoning is right about the car and
wrong about what to draw: the balancing is a few percent at the very end, and
modelling it as a decay across the last tenth of the pack moved every milestone.

The consequence is that the forecast can now finish earlier than the car's own
"time remaining", which is on the same screen. Rather than print two finishing
times and leave the reader to decide which is broken, the milestone card says what
the car thinks whenever the two differ by more than a quarter of an hour.

### Above 10 kW the shape comes from the car

The bigger change. A fast charge does taper, and the shape belongs to the pack —
its chemistry, its age, how the car chooses to treat it. Every previous version
modelled that shape as a rate falling linearly with charge, which was a placeholder
for a curve nobody had.

The car has the curve. It drives it every time it fast-charges and the app is
already watching, so `ChargeCurveProfile` now accumulates mean charging power
against state of charge, in five-percent buckets, across every DC session it sees.
Once enough buckets above the current charge have readings, the forecast uses that
measured shape.

What the profile does *not* supply is scale. The live reading does that, because a
cold pack or a shared cabinet changes the height of the curve without changing its
shape, and a single factor across the whole curve is fitted so the total still
lands on the car's own finishing time. Shape from history, scale from now, endpoint
from the car.

Deliberate refusals, all for the same reason — a forecast built on the wrong
evidence is worse than one that admits it is fitted:

- **Wall-box readings are not learned from.** They are flat and would drag a taper
  towards a straight line it does not have.
- **A bucket needs three readings** before it is trusted, and a profile needs
  coverage *above* the current charge. Readings from the bottom of the pack say
  nothing about the top.
- **Beyond the readings the curve holds rather than extrapolating.** A taper
  extended past the evidence heads for zero and predicts a charge that never
  finishes.
- **A scale factor outside 0.4–2.5 means no fit.** The profile then disagrees with
  today by more than conditions explain, and the fitted fallback is used instead.
- **Nothing is learned in demo mode.**

The card says "From this car's own charging history" when a forecast is built this
way, because that is a different degree of confidence from a fitted assumption and
an owner deciding whether to wait for 80% is entitled to know which they are
reading.

### Under the hood

`ChargeProjection` now carries a `Shape` — flat, knee, or learned — and one numeric
integrator serves all three. The analytic special cases were replaced deliberately:
a learned curve has no closed form, and three integrators that have to be kept
agreeing with each other is a worse thing to own than one that is obviously right.

The profile is stored on `VehicleRecord` as encoded JSON, optional so the store
migrates in place. It is written once when a charge ends or the app backgrounds,
not on every reading.

## Verification

- 508 unit and UI tests passing before the archive.
- `ChargeCurveProfileTests` pins every refusal above: wall boxes not learned from,
  one reading not trusted, coverage judged above the current charge, the curve
  holding beyond its readings, and a round trip through storage.
- `testAWallBoxHoldsItsRateForTheWholeSession` and `testAWallBoxPowerForecastIsLevel`
  pin the flat case that 1.8.7 got wrong.
- `testAFastChargeUsesTheShapeLearnedFromThisCar`,
  `testALearnedShapeIsScaledToTheCarsFinishingTime` and
  `testAProfileThatDoesNotCoverTheClimbIsNotUsed` pin the learned path.
- Both demos rendered and looked at. The wall-box demo now draws a level power line
  and a straight charge line, which is what a 7 kW charger does.

## Known gaps

- **The learned path has never run on real history.** No profile exists until a car
  has been watched fast-charging several times, so every screenshot of it so far is
  from a synthetic profile in a test. The first real Supercharger sessions are what
  will tell whether the bucket width, the three-reading threshold and the coverage
  rule are set anywhere near right.
- A profile learned across seasons will average a cold pack with a warm one. The
  scale factor absorbs some of that; whether it absorbs enough is unknown.
- Charge details already fetched for the history screens are not folded into the
  profile, only live sessions. That is a missed source of readings for anyone whose
  history predates this build.
