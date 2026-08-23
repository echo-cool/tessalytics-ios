# Tessalytics 1.8.6 (202608231439)

TestFlight build. 1.6.0 still holds the editable version record, so this train
carries beta notes only.

    ASC_METADATA=release/tessalytics-1.8.6/metadata:app-store/metadata

## A forecast for a car on a charger

A charging car is a car somebody has walked away from, and the app had nothing to
say about when to come back beyond the car's own single "time to full". This train
adds the rest: the charge an hour ahead, a clock time for every ten percent between
here and the limit, and a chart of both — in the hero card, where the seven-day
battery history sits when the car is not plugged in. That history is the right thing
to show a parked car and the wrong thing to show one on a charger; the question has
changed from "how has it been doing" to "when can I leave".

### The modelling, and what it refuses to do

Charging is not one shape. A wall box holds its rate — 7 kW at 20% and 7 kW at 79% —
and a straight line is not an approximation, it is what happens. A Supercharger's
rate falls away as the pack fills, and a straight line drawn from the current rate
promises an hour that will not arrive. That is worse than saying nothing, because
somebody plans around it.

So no charging curve is baked in. There is no table of tapers per model, supplier or
cabinet, because any such table would be wrong for some pack at some temperature.
Instead **one number is fitted to two measurements the car itself provides**: the
rate right now, and the time the car says it needs to reach the limit.

- If those agree, the rate is flat, the projection is a straight line, and the card
  says nothing about tapering.
- If the car says it needs longer than the current rate implies, that difference
  **is** the taper. The rate is modelled as falling linearly with charge, and the
  one free parameter is bisected until the model's finishing time lands on the car's
  own. `t(s) = ln(1 + kΔ/r₀)/k` has no closed-form inverse; sixty halvings put it
  well inside a millisecond.
- If the car expects to do *better* than the rate measured this instant — a pack
  still warming — its estimate is the better evidence and wins.

The rate itself is measured from the car's reported charge over the last twelve
minutes, not derived from charger power. Nameplate power ignores charging losses, a
cold pack, a shared cabinet and a car that has decided to draw less than it could; a
measured rate has all of that in it already. Below three minutes of spread it
declines to report a rate at all — a level reported in whole percent, divided by
twenty seconds, is either zero or enormous, and both would be shown to somebody as a
plan.

### Two axes, because there are two stories

Charge climbs and flattens; power holds and then falls, and the fall in power is
what *causes* the flattening. On one axis either the power line is a flat smear
along the bottom or the charge line is squashed into the top, and the relationship —
the whole explanation for why the last ten percent takes as long as the first thirty
— disappears.

Solid is measured, dashed is forecast, and the chart marks both when the car was
plugged in and where "now" is.

### Three bugs found by looking at it

- **The forecast line drew solid, in the measured line's colour.** Swift Charts
  joins every `LineMark` sharing the x and y roles into one line and one style
  unless each carries a `series` value — which erased the only thing separating a
  reading from a guess.
- **The measured and forecast power lines did not meet.** Forecast power was
  computed as rate × pack capacity, which is tidy and wrong: usable capacity is not
  rated capacity and reported charger power includes losses the pack never sees, so
  the two disagreed by tens of kilowatts and the chart showed a step at exactly the
  point a reader is looking. It is now scaled from the reported power in proportion
  to the rate, which makes them meet by construction and reduces the claim to the
  one actually being made.
- **The right-hand axis was labelled "139 kW" and "51 kW"** — the charge axis
  showing through. It now ticks at round kilowatts.

## Verification

- 483 unit and UI tests, all passing before the archive; 33 new.
- `ChargeProjectionTests` pins the flat case, the tapering case, that the fit lands
  on the car's own finishing time, that the hourly figure stops at the limit, that a
  milestone above the limit has no time rather than an invented one, and that the
  forecast power continues from the reported power rather than restarting.
- `LiveChargeSessionTests` pins what the rate measurement *refuses* to do: too short
  a span, and a level that has not ticked over, are both "no rate" rather than a
  wild one.
- The demo's charging data is generated from a single rate curve and integrated
  backwards from the reported level, so the measured and forecast halves are two
  halves of one story. An earlier version claimed 118 kW beside a level climbing at
  60 %/h, which on a 78 kWh pack is arithmetically impossible — and it showed.

## Known gaps

- **No forecast has been checked against a real charge yet.** Every figure here is
  exercised against generated data and unit tests. The hour-ahead number and the
  taper's shape are the two things worth watching on a real Supercharger, and the
  beta notes ask for exactly that.
- The rate window is twelve minutes. On a charger that changes output sharply — a
  stall being shared mid-session — the forecast will lag that change by a few
  minutes before catching up.
- A scheduled charge that has not started yet is treated as not charging, which is
  correct but means the card appears only once current is flowing.
