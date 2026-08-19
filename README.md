# Tessalytics: TeslaMate Client

**Understand every drive.**

Tessalytics is a privacy-focused native iOS companion for self-hosted [TeslaMate](https://github.com/teslamate-org/teslamate) installations. It connects directly from your iPhone to your own [TeslaMateApi](https://github.com/tobiasehlert/teslamateapi) server. An optional direct Owner API connection adds live vehicle state and a small set of confirmed controls. There is no Tessalytics cloud, tracking, or advertising.

> **Unofficial project:** This project is an unofficial community tool and is not affiliated with, endorsed by, or supported by the official TeslaMate project or Tesla, Inc.

## Project status

Tessalytics is early open-source software. The repository contains a native Swift 6/iOS 18 application with secure onboarding, multi-server and multi-vehicle selection, offline history, status, drives and route maps, charging analysis, battery-health estimates, firmware history, analytics, tests, and public documentation. Expect API-compatibility refinements as TeslaMateApi evolves.

## Screenshots

| Onboarding | Vehicle status | Drive route | Analytics |
|---|---|---|---|
| _Screenshot coming soon_ | _Screenshot coming soon_ | _Screenshot coming soon_ | _Screenshot coming soon_ |

## Features

- Live-or-last-reported vehicle dashboard with honest freshness labels
- Drive and charging history with incremental synchronization and offline access
- Route maps with Douglas–Peucker downsampling and charts for large tracks
- Charging curves, energy, efficiency, cost, and effective-price analysis
- Battery-health estimates with explicit data-quality language
- Firmware update history and period-based analytics
- On-device travel, charging-time, charging-cost, and efficiency forecasts with visible confidence
- Actionable anomaly and savings signals based on rolling historical comparisons
- Optional local alerts for low battery, predicted charge completion, software updates, and important anomalies
- Multiple TeslaMate servers and vehicles
- Bearer token, HTTP Basic, and trusted-private-network authentication modes
- Optional Owner API token-pair connection for live state and lock, climate, charging, and trunk controls
- Every direct command requires confirmation and Face ID or the device passcode
- TeslaMate credentials use Keychain After First Unlock; Owner API tokens use When Unlocked, This Device Only
- No automatic vehicle wake-ups, Tesla password collection, third-party SDKs, or TLS bypass

## Requirements

1. A working [TeslaMate](https://github.com/teslamate-org/teslamate) installation
2. [TeslaMateApi](https://github.com/tobiasehlert/teslamateapi) deployed alongside TeslaMate
3. Secure network access from the iPhone to every TeslaMateApi route
4. Xcode 16 or later, Swift 6, and an iOS 18 or later deployment target for development

See [Backend setup](docs/backend-setup.md) before exposing any service to a network.

> **Security warning:** TeslaMateApi’s built-in `API_TOKEN` does not protect all read-only endpoints. It primarily protects command and logging operations. If TeslaMateApi is exposed outside a trusted private network, place authentication in front of every API route using a reverse proxy or VPN.

Never expose PostgreSQL, Mosquitto/MQTT, Owner API tokens, or an unprotected TeslaMateApi service.

## Build

The generated Xcode project is checked in. [XcodeGen](https://github.com/yonaskolb/XcodeGen) is needed only after changing `project.yml`.

```sh
git clone git@github.com:echo-cool/tessalytics.git
cd tessalytics
```

```sh
xcodegen generate
xcodebuild -project Tessalytics.xcodeproj \
  -scheme Tessalytics \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build
```

Run tests:

```sh
xcodebuild -project Tessalytics.xcodeproj \
  -scheme Tessalytics \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test
```

No backend URL or token is required to compile or run deterministic tests. Optional live integration variables are documented in [Testing](docs/testing.md).

## Configure a server

On first launch, enter a profile name, the URL of your protected TeslaMateApi endpoint, and its authentication. Tessalytics tests unauthenticated `/api/ping`, then authenticated `/api/v1/cars`, before saving the profile. Server metadata is stored in SwiftData; credentials are stored separately in Keychain. The optional Owner API connection is configured later in Settings using an access-token and refresh-token pair generated outside Tessalytics; the app never asks for a Tesla password.

HTTPS is required for remote servers. Local HTTP is available only when explicitly enabled and only for common private-network or local hostnames. Tessalytics never disables certificate validation or silently changes HTTPS to HTTP.

For deployment examples and secure access options including Tailscale, Caddy, nginx, and Traefik, see [Backend setup](docs/backend-setup.md).

## Architecture

```text
SwiftUI features
    ↓
Repositories and analytics services
    ↓
Typed TeslaMateApi client ──┬── Keychain credentials
Owner API session actor ────┘   SwiftData offline cache
    ↓
URLSession
```

The application uses SwiftUI, Observation, structured concurrency, URLSession, Codable, SwiftData, MapKit, Swift Charts, UserNotifications, Security, XCTest, and XCUITest. It has no third-party runtime dependencies. See [Architecture](docs/architecture.md), [Intelligence methodology](docs/intelligence.md), and [API compatibility](docs/api-compatibility.md).

## Privacy

Tessalytics connects directly from the user’s device to the server configured by that user and, when enabled, Tesla’s unofficial Owner API. It includes no developer-operated cloud, ads, analytics SDK, or telemetry. Location history cached for offline use remains in the app container. See [PRIVACY.md](PRIVACY.md).

## Contributing and security

Contributions are welcome under [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md). Please report vulnerabilities according to [SECURITY.md](SECURITY.md), not in a public issue.

TeslaMate is a separate project. Review its [trademark policy](https://github.com/teslamate-org/teslamate/blob/main/TRADEMARK.md) before proposing branding changes.

## Known limitations

- Tessalytics never wakes a sleeping vehicle automatically; direct commands can fail while it is asleep.
- Current status depends on TeslaMateApi’s MQTT connection and can represent the last poll.
- The optional Owner API is unofficial and may change or stop working without notice.
- Historical pagination does not expose a total count, so end-of-list detection is heuristic.
- Server-provided fields vary across TeslaMate/TeslaMateApi versions and installations.
- Predictions are statistical estimates based on synchronized history, not guarantees or vehicle safety instructions.
- Status alerts are evaluated when the app refreshes; predicted charging-completion alerts can then remain scheduled after the app closes.
- Custom certificate authorities are not currently supported; certificate validation is never bypassed.
- iPad-specific layouts and App Store distribution metadata remain future work.

## License

Tessalytics is available under the [MIT License](LICENSE).
