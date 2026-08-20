# Architecture

Tessalytics is a Swift 6, SwiftUI, iOS 18 application organized around user-facing features and replaceable core services.

## Layers

- `App`: composition, app lifecycle, selected server and vehicle, foreground status polling
- `Core/API`: the `VehicleDataAPI` protocol and its Tessalytics Backend client, authentication injection, validation, retry, cancellation
- `Core/Authentication`: Keychain protocol and Security-framework implementation
- `Core/Models`: defensive transport and domain models
- `Core/Persistence`: SwiftData records keyed by server, car, record kind, and backend ID
- `Core/Synchronization`: repository protocols, newest-page refresh, incremental history, immutable-detail cache
- `Core/Analytics`: documented calculations and trapezoidal sample integration
- `Core/Intelligence`: deterministic forecasts, confidence scoring, anomaly detection, and opportunity signals
- `Core/Notifications`: local-notification planning and isolated scheduling
- `Features`: onboarding, dashboard, drives, charging, battery, analytics, intelligence, updates, settings, privacy, and about
- `SharedUI`: reusable accessible state and metric components

## Data lifecycle

Current status is volatile. The dashboard polls at 60-second intervals only while visible and foregrounded. It stops when backgrounded or dismissed, never requests wake-up, and labels previous data stale after network failure.

Drive and charge summaries are fetched newest-first in pages of 30 and upserted by stable backend ID. Completed detail records are encoded into an externally stored SwiftData payload and retained indefinitely. In-progress charge details are not treated as immutable. Battery-health estimates refresh after approximately one day.

All cache keys include the server UUID and car ID. Credentials are never part of a SwiftData model.

## Concurrency

Networking uses async/await and cancellation-aware retry. UI and SwiftData repositories run on the main actor. Immutable `Sendable` history samples cross into a dedicated intelligence actor for analysis. Local-notification scheduling is isolated in a separate actor. Large route simplification runs in a detached task before MapKit overlays are built. DTOs are `Sendable`.

## Security boundaries

Authentication headers are created immediately before a request. No request or response logging includes sensitive headers or body content. TLS remains under URLSession’s standard trust evaluation. `401` maps to bad credentials while `403` remains a distinct forbidden/disabled result.
