# Testing

## Deterministic tests

Tests use sanitized bundled JSON and an injected HTTP transport. They do not require a server.

Run both the unit and UI targets after every feature change. A feature is not complete until both suites pass. During local development, record the test destination and result in the gitignored `notes/TESTING.md` handoff log.

```sh
xcodegen generate
xcodebuild -project Tessalytics.xcodeproj \
  -scheme Tessalytics \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test
```

The two targets can also be run independently while diagnosing failures:

```sh
xcodebuild -project Tessalytics.xcodeproj \
  -scheme Tessalytics \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:TessalyticsTests \
  test

xcodebuild -project Tessalytics.xcodeproj \
  -scheme Tessalytics \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:TessalyticsUITests \
  test
```

The suite covers envelope and snake-case decoding, null/missing/unknown fields, dates and sentinels, mixed units, authentication headers, HTTP error mapping, pagination, cancellation, Keychain abstraction replacement, cached last-known vehicle status, generated demo seeding and relaunch persistence, route simplification, analytics integration, forecast generation, anomaly detection, notification planning, secret redaction, and UI smoke paths.

## Optional live integration

Live integration must be explicitly enabled outside version control. The helper prompts for the Bearer token without echoing it, injects it into an ephemeral test-run configuration, runs only the live contract tests, and removes the credential configuration immediately afterward:

```sh
./scripts/run-live-tests.sh 'https://protected.example.invalid' 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The Xcode destination is optional when the default simulator exists. No default test performs network requests. Keep real domains and tokens out of fixtures, schemes, `.xcconfig` files, result bundles, screenshots, and CI logs.

## UI smoke modes

UI tests launch sanitized, network-free app modes using test-only process arguments. They cover onboarding, the public Explore Demo transition, the home driving chart, direct-control visibility with and without tokens, route-preview drive cards, compact drive details, charge history, analytics, battery health, and intelligence screen availability. These modes do not contain a backend URL, credential, private vehicle name, or real location.

| Argument | What it does |
| --- | --- |
| `-ui-demo` | Generated sample data, no network |
| `-ui-demo-offline` | The same car, asleep and reporting nothing |
| `-ui-demo-driving` | One frozen instant of a journey — what the screenshot sets capture |
| `-ui-demo-driving-live` | Advances that journey at the rate a car publishes: an acceleration, a red light at ~26s, and Full Self-Driving from ~58s, repeating every two minutes |
| `-ui-demo-gappy-readings` | A third of those readings arrive with no position at all |
| `-ui-owner-disconnected` | No Owner API tokens, so direct controls are hidden |
| `-ui-onboarding` | The first-run screens |

The last two of the demo-driving arguments exist for one regression each, and both
are worth keeping.

`-ui-demo-driving-live` is the only way to see a screen that is bound to a stream
without owning a moving car: a map that never moves cannot show a map that flickers
while it moves, and a speed that is always 63 mph cannot show what the screen says
at a red light.

`-ui-demo-gappy-readings` reproduces the fault behind the reported flashing map.
The hero card used to have two layouts, one with a map and one without, so a single
reading that arrived with no position swapped the whole card — and a `Map` that
leaves the view tree comes back as an empty map surface until MapKit redraws it.
In dark mode that read as the card's red, then black, then red again, several times
a minute for a whole drive. `LiveDrivingUITests` holds the map on screen through
eight seconds of that fault.
