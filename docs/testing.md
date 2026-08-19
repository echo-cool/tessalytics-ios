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

The suite covers envelope and snake-case decoding, null/missing/unknown fields, dates and sentinels, mixed units, authentication headers, HTTP error mapping, pagination, cancellation, Keychain abstraction replacement, route simplification, analytics integration, forecast generation, anomaly detection, notification planning, secret redaction, and UI smoke paths.

## Optional live integration

Live integration must be explicitly enabled outside version control:

```sh
export TESSALYTICS_TEST_BASE_URL='https://protected.example.invalid'
export TESSALYTICS_TEST_API_TOKEN='replace-me'
```

No default test reads these variables and they must never be printed. Keep real domains and tokens out of fixtures, schemes, `.xcconfig` files, result bundles, screenshots, and CI logs.

## UI smoke modes

UI tests launch sanitized, network-free app modes using test-only process arguments. They cover onboarding, dashboard, drive history, charge history, analytics, battery health, and intelligence screen availability. These modes do not contain a backend URL, credential, private vehicle name, or real location.
