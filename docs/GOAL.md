# Original product brief

> This file preserves the project’s original read-only version-one brief for historical context. The current product scope is documented in `README.md`; version 1.1 adds an optional, locally stored Owner API token connection for live state and explicitly confirmed vehicle controls without automatic wake-ups.

You are responsible for implementing a production-quality, open-source native iOS application named **Tessalytics**.

The full descriptive title is:

**Tessalytics: TeslaMate Client**

Do not stop after producing a plan. Inspect the workspace, create the project, implement the application, run all available tests, and leave the repository in a usable and documented state.

# 1. Product goal

Build a privacy-focused, read-only native iOS client for self-hosted TeslaMate installations.

Tessalytics should let users:

* Monitor current vehicle status
* Browse drive history
* View individual routes on a map
* Browse charging history
* Analyze individual charging sessions
* Examine battery-health information
* Review software-update history
* Analyze mileage, energy consumption, efficiency, and charging cost
* Use previously synchronized data while offline
* Connect to multiple TeslaMate servers
* Monitor multiple vehicles

The application must not send commands to vehicles in version one.

# 2. Open-source identity

This will be an open-source community project.

Use:

* **Product name:** Tessalytics
* **Descriptive title:** Tessalytics: TeslaMate Client
* **Repository name:** `tessalytics`
* **Suggested bundle identifier:** `com.yourname.Tessalytics`
* **Tagline:** Understand every drive.
* **Suggested license:** MIT, unless the existing repository specifies another license

Create an original icon and visual identity. Do not use:

* The official Tesla logo
* The official TeslaMate logo
* TeslaMate dashboard artwork
* Tesla vehicle renders copied from Tesla
* Branding that suggests official endorsement

Include this disclaimer prominently in the README and the app’s About screen:

> This project is an unofficial community tool and is not affiliated with, endorsed by, or supported by the official TeslaMate project or Tesla, Inc.

Always spell **TeslaMate** with this capitalization.

Link to:

* TeslaMate: https://github.com/teslamate-org/teslamate
* TeslaMateApi: https://github.com/tobiasehlert/teslamateapi
* TeslaMate trademark policy: https://github.com/teslamate-org/teslamate/blob/main/TRADEMARK.md

Do not copy code from other mobile clients such as T-Buddy or MateDrive. This must be an original implementation based on the TeslaMateApi interface.

# 3. Backend architecture

Tessalytics communicates with TeslaMateApi:

https://github.com/tobiasehlert/teslamateapi

The data flow is:

```text
Tesla vehicle
    ↓
TeslaMate
    ├── PostgreSQL historical data
    └── MQTT live snapshot
            ↓
       TeslaMateApi
            ↓
Authenticated HTTPS reverse proxy
            ↓
       Tessalytics
```

Important behavior:

* TeslaMateApi does not independently poll the vehicle.
* Data freshness is controlled by TeslaMate.
* If a vehicle is asleep or offline, status values may represent the last available poll.
* The app must never wake a vehicle.
* Completed drives and charging sessions are effectively immutable.
* Current status is volatile and must not be permanently cached as current data.
* Historical data can be cached aggressively.
* Drive and charge detail records can be cached permanently by ID once complete.

The user’s current backend is reachable at:

```text
https://tesla-api.echo.cool
```

However:

* Do not hardcode this URL in the source.
* Do not commit it to public fixtures or configuration.
* Do not include this private deployment URL in the public README.
* The user must enter the server URL through onboarding.
* Development integration configuration must use an ignored local `.xcconfig`, environment variables, or an ignored JSON configuration file.
* Never commit real bearer tokens, VINs, coordinates, addresses, vehicle names, or server credentials.

# 4. Public README backend documentation

The public README must explain that Tessalytics requires:

1. A working TeslaMate installation
2. TeslaMateApi deployed alongside TeslaMate
3. Secure network access from the iPhone to TeslaMateApi

Link directly to the upstream API project:

https://github.com/tobiasehlert/teslamateapi

Include generic TeslaMateApi deployment instructions or a generic Docker Compose example with placeholder values.

Do not document the user’s private:

* Domain
* Cloudflare Tunnel
* Tunnel hostname
* nginx files
* Filesystem paths
* Token-rotation process
* Server IP addresses
* Docker gateway binding
* Personal TeslaMate configuration

The public documentation may describe generic deployment options such as:

* Tailscale or another VPN
* A trusted HTTPS reverse proxy
* Caddy, nginx, or Traefik
* HTTP Basic Authentication
* Bearer-token authentication enforced by the reverse proxy

Include a prominent warning:

> TeslaMateApi’s built-in `API_TOKEN` does not protect all read-only endpoints. It primarily protects command and logging operations. If TeslaMateApi is exposed outside a trusted private network, place authentication in front of every API route using a reverse proxy or VPN.

Do not suggest exposing:

* PostgreSQL
* Mosquitto/MQTT
* TeslaMateApi directly without access control
* Tesla account tokens

# 5. Current backend authentication

For the current deployment, all requests except `/api/ping` require:

```http
Authorization: Bearer <TOKEN>
```

Behavior:

* Missing or incorrect token returns `401`
* The response is normally:

```json
{"error":"unauthorized"}
```

The bearer token is enforced by the reverse proxy, not by TeslaMateApi itself.

Treat this token as a sensitive location-tracking credential because it protects:

* VIN
* Current location
* Historical routes
* Start and end addresses
* Charging locations
* Live vehicle status

Store credentials only in Keychain.

Use:

```swift
kSecAttrAccessibleAfterFirstUnlock
```

This permits authorized background refresh after the device has been unlocked following a reboot.

Never store the token in:

* `UserDefaults`
* `Info.plist`
* Source code
* Committed `.xcconfig` files
* SwiftData
* Debug logs
* Crash reports

For the general open-source client, support:

* Bearer-token authentication
* HTTP Basic Authentication
* No application-level authentication for explicitly private/VPN-only installations

Display a warning when the user selects no authentication.

Do not disable TLS certificate validation. Do not implement an “accept any certificate” option.

# 6. Technology requirements

Use:

* Swift 6
* SwiftUI
* Minimum deployment target iOS 18
* Structured concurrency
* async/await
* `URLSession`
* `Codable`
* SwiftData
* Swift Charts
* MapKit
* Security/Keychain APIs
* Observation using `@Observable`
* XCTest
* XCUITest
* Apple frameworks wherever practical

Avoid third-party dependencies unless they provide a major, documented benefit.

Use a feature-oriented architecture similar to:

```text
Tessalytics/
  App/
  Core/
    API/
    Authentication/
    Models/
    Persistence/
    Synchronization/
    Formatting/
    Utilities/
  Features/
    Onboarding/
    Dashboard/
    Drives/
    Charges/
    Battery/
    Analytics/
    Updates/
    Settings/
    About/
  SharedUI/
TessalyticsTests/
TessalyticsUITests/
docs/
```

Use protocols for the API client, repositories, Keychain access, synchronization, and analytics so they can be replaced by mocks in tests.

# 7. API endpoints

All primary endpoints are under `/api/v1`.

Implement typed support for:

| Method | Endpoint                                  | Purpose                              |
| ------ | ----------------------------------------- | ------------------------------------ |
| `GET`  | `/api/ping`                               | Unauthenticated reachability check   |
| `GET`  | `/api/v1/cars`                            | Vehicle list and lifetime statistics |
| `GET`  | `/api/v1/cars/{carId}`                    | Vehicle information                  |
| `GET`  | `/api/v1/cars/{carId}/status`             | Current MQTT-backed snapshot         |
| `GET`  | `/api/v1/cars/{carId}/battery-health`     | Capacity, range, and degradation     |
| `GET`  | `/api/v1/cars/{carId}/drives`             | Paginated drive summaries            |
| `GET`  | `/api/v1/cars/{carId}/drives/{driveId}`   | Drive details and complete GPS track |
| `GET`  | `/api/v1/cars/{carId}/charges`            | Paginated charging sessions          |
| `GET`  | `/api/v1/cars/{carId}/charges/{chargeId}` | Charging session samples and details |
| `GET`  | `/api/v1/cars/{carId}/charges/current`    | In-progress charging session         |
| `GET`  | `/api/v1/cars/{carId}/updates`            | Firmware history                     |
| `GET`  | `/api/v1/globalsettings`                  | TeslaMate settings and units         |

Never assume a vehicle ID. Always request `/cars` and use the returned identifiers.

Support these query parameters:

* `page`
* `show`
* `startDate`
* `endDate`
* `location`
* `minDistance` for drives
* `maxDistance` for drives

Pagination is one-indexed.

Use an initial page size of approximately 25–50 records. Do not download the user’s entire history at launch.

# 8. Commands are unsupported

The current backend disables command, wake-up, and logging-control routes.

These operations return `403`:

```text
POST /api/v1/cars/{id}/command/{command}
POST /api/v1/cars/{id}/wake_up
PUT  /api/v1/cars/{id}/logging/{command}
```

Do not add UI controls for:

* Lock or unlock
* Climate
* Trunk or frunk
* Charging control
* Sentry control
* Remote start
* Wake-up
* Logging suspend/resume
* Window control
* Software installation

Model `401` and `403` separately:

* `401`: authentication failed
* `403`: operation disabled or forbidden

Never redirect the user to re-enter a valid token merely because an unsupported operation returned `403`.

# 9. Response conventions

Most responses use a generic `data` envelope:

```json
{
  "data": {
    "cars": []
  }
}
```

Implement one reusable model:

```swift
struct Envelope<T: Decodable>: Decodable {
    let data: T
}
```

Many responses include repeated `car` and `units` objects. Model this shared structure consistently.

API keys are snake_case. Choose one consistent decoding strategy:

* `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase`, or
* Explicit `CodingKeys`

Do not mix strategies unpredictably.

Inspect the current TeslaMateApi source for the exact response structures. Do not guess model fields when the backend source provides the contract.

# 10. Defensive decoding

Many fields can legitimately be `null`.

Model nonessential fields as optional, including examples such as:

* Inside temperature
* Outside temperature
* Charging cost
* End date
* Battery range
* Tire pressure
* Charger brand
* Geofence
* Address
* Charging voltage
* Charging current
* Scheduled charging time

Do not display missing numeric data as zero.

Use:

* `Unavailable`
* `Not reported`
* `No cost configured`
* Similar context-appropriate labels

Unknown JSON fields must not cause decoding failures.

Create sanitized fixtures that contain:

* Null fields
* Missing fields
* Unknown fields
* Empty arrays
* Multiple vehicles
* An in-progress drive
* An in-progress charge
* A completed drive
* A completed charge
* Authentication errors
* Invalid server responses

# 11. Dates

Dates normally use RFC 3339 with an explicit offset, for example:

```text
2026-08-18T21:28:22-07:00
```

Support:

* RFC 3339 with offsets
* ISO 8601 with fractional seconds
* ISO 8601 without fractional seconds

A known invalid sentinel can appear for an unset scheduled charging time:

```text
0000-12-31T16:07:02-07:52
```

Treat:

* Years earlier than 1900
* Year zero
* Structurally invalid offsets
* Unparseable optional dates

as “not scheduled” or `nil`.

Do not fail the entire response because an optional scheduled date contains an invalid sentinel.

# 12. Units

TeslaMate may return mixed unit preferences, for example:

```json
{
  "unit_of_length": "mi",
  "unit_of_pressure": "psi",
  "unit_of_temperature": "C"
}
```

Never infer all units from device locale.

Read and respect each server-provided unit independently.

Convert values into Foundation `Measurement` types near the API boundary and keep a consistent internal representation.

Support:

* Miles and kilometers
* mph and km/h
* Celsius and Fahrenheit
* psi and bar
* kWh
* Wh/mi and Wh/km
* Configurable currency formatting

Allow an optional app-level display override without changing TeslaMate’s settings.

# 13. Networking layer

Create a typed API client with:

* Configurable base URL
* Configurable authentication method
* Authentication-header injection
* async/await
* Cancellation support
* Request timeouts
* Status-code validation
* Safe redacted logging
* Retry for transient idempotent requests only
* No retry for `401`
* No credential logging
* Decoding through the generic envelope
* Testable `URLSession` injection

Model at least:

```swift
enum ClientError: Error {
    case invalidConfiguration
    case transport
    case badToken
    case forbidden
    case notFound
    case backendUnavailable
    case decoding
    case unexpectedStatus(Int)
}
```

Handle:

* `200`: success
* `401`: invalid credentials
* `403`: forbidden or disabled
* `404`: missing resource
* `429`: rate limited
* `500`: server error
* `502`, `503`, `504`: backend unavailable

Use `/api/ping` to test reachability, followed by an authenticated `/api/v1/cars` request to verify credentials and API compatibility.

# 14. Onboarding

Create a polished onboarding flow containing:

* Explanation of TeslaMate and TeslaMateApi prerequisites
* Link to TeslaMateApi deployment documentation
* Server URL field
* Authentication-method selection
* Bearer token or Basic Auth fields
* Test Connection button
* Reachability result
* Authentication result
* API compatibility result
* Secure-save confirmation
* Clear troubleshooting guidance

Normalize the base URL:

* Remove unnecessary trailing slashes
* Reject malformed URLs
* Require HTTPS for normal remote servers
* Allow local HTTP only for an explicitly selected development or private-network configuration
* Never silently downgrade HTTPS to HTTP

# 15. Dashboard

The dashboard should display available data such as:

* Vehicle name
* Model and trim
* Current state
* Logger health
* Last-updated time
* Battery percentage
* Usable battery percentage
* Estimated range
* Rated range
* Charging state
* Charging power
* Charging progress
* Time remaining
* Current or last-known location
* Inside and outside temperatures
* Lock state
* Door/window/trunk/frunk status
* Sentry status
* Odometer
* Tire pressures
* Software version

Clearly distinguish:

* Live
* Last updated
* Stale
* Asleep
* Offline
* Unavailable

Do not imply that data is live merely because it was successfully fetched.

Poll `/status` approximately every 60 seconds while the dashboard is visible and the application is foregrounded.

Rules:

* Never poll faster than 30 seconds.
* Stop status polling when the app backgrounds.
* Stop polling when the dashboard is no longer visible.
* Do not wake the vehicle.
* Do not permanently cache status as current.
* The last snapshot may be retained only for an explicitly labeled offline/stale display.

# 16. Drive history

Implement:

* Reverse chronological list
* Pagination
* Date filtering
* Location filtering
* Minimum and maximum distance filtering
* Pull to refresh
* Incremental loading
* Offline display
* Empty states
* Error states
* Stale-data indicators

Use the summary endpoint for the list.

Do not fetch full GPS tracks while rendering the drive list.

Each row should show available fields such as:

* Start time
* End time
* Start location
* End location
* Distance
* Duration
* Average speed
* Maximum speed
* Energy consumption
* Efficiency
* Temperature

# 17. Drive details

Fetch `/drives/{driveId}` only when the user opens a drive.

Display:

* Route map
* Start marker
* End marker
* Start and end addresses
* Distance
* Duration
* Speed chart
* Power chart
* Elevation chart
* Temperature chart
* Battery or range change
* Energy consumption
* Efficiency
* Maximum speed
* Ascent and descent
* Shareable textual summary

Drive-detail payloads may contain many thousands of GPS points.

Requirements:

* Decode off the main actor
* Do not block UI rendering
* Downsample before creating `MKPolyline`
* Preserve start/end points
* Preserve meaningful turns and route shape
* Use an established simplification algorithm such as Douglas–Peucker
* Cache the original detail response or normalized detail data
* Cache completed drive details permanently by ID

# 18. Charging history

Implement:

* Reverse chronological list
* Pagination
* Date filtering
* Location filtering
* Pull to refresh
* Offline display
* Current charging-session indicator

Each row should show available fields such as:

* Start and end time
* Location
* Energy added
* Energy used
* Duration
* Starting battery percentage
* Ending battery percentage
* Cost
* Fast-charger status
* Charger type or brand

# 19. Charge details

Display available information such as:

* Battery-level curve
* Charging-power curve
* Voltage
* Current
* Energy added
* Energy drawn
* Charging efficiency
* Duration
* Cost
* Effective price per kWh
* Location
* Geofence
* Charger type
* Charger brand
* Outside temperature

If energy used or cost is unavailable, do not fabricate charging efficiency or price-per-kWh metrics.

Cache completed charge details permanently by ID.

Refresh an in-progress charging session periodically while visible. Stop when the app backgrounds.

# 20. Battery health

Use `/battery-health` as the primary battery-health source.

Display available information such as:

* Initial or maximum estimated capacity
* Current estimated capacity
* Capacity loss
* Degradation percentage
* Projected range
* Trend over time
* Data timestamp
* Data-quality explanation

Do not describe an estimate as a physical battery-capacity measurement.

Cache battery-health data for approximately one day.

# 21. Software updates

Display:

* Installed version
* Installation time
* Update history
* Current version when available

Do not provide an installation command.

# 22. Analytics

Create an analytics dashboard with selectable periods:

* 7 days
* 30 days
* Current month
* Previous month
* Current year
* All time
* Custom range

Implement defensible metrics such as:

* Total distance
* Total driving time
* Drive count
* Average trip distance
* Total charging energy
* Total charging cost
* Average charging price per kWh
* Average driving efficiency
* Monthly distance trend
* Monthly charging-energy trend
* Monthly charging-cost trend
* Efficiency versus temperature
* Charging by location
* AC versus DC charging
* Most common destinations
* Most common routes when data supports it
* Battery-health trend

Prefer values already calculated by TeslaMateApi.

If a metric is calculated locally:

* Put the formula in a dedicated analytics service.
* Add unit tests.
* Document assumptions.
* Identify estimates as estimates.
* Do not silently substitute zero for missing data.

If energy must be estimated from timestamped power samples, integrate using timestamp intervals and the trapezoidal rule. Handle irregular intervals and gaps.

# 23. SwiftData persistence

Persist:

* Server profiles without credentials
* Vehicles
* Global settings
* Drive summaries
* Charge summaries
* Completed drive details
* Completed charge details
* Battery-health observations
* Firmware history
* Synchronization metadata
* Last known status snapshot only when clearly labeled stale

Never persist credentials in SwiftData.

Use stable backend IDs for upserts.

Requirements:

* Avoid duplicates
* Preserve data across launches
* Fetch the newest page first
* Refresh page one on pull-to-refresh
* Load older pages incrementally
* Preserve offline data during network failures
* Record the last successful synchronization
* Handle deleted or unavailable servers gracefully
* Support multiple server profiles
* Partition cached records by server and vehicle

Caching policy:

| Data                     | Policy                                           |
| ------------------------ | ------------------------------------------------ |
| Status                   | Do not treat as persistent current data          |
| Cars                     | Cache for the session and persist basic metadata |
| Global settings          | Cache for the session                            |
| Drive summaries          | Persist and refresh recent pages                 |
| Charge summaries         | Persist and refresh recent pages                 |
| Completed drive details  | Cache permanently                                |
| Completed charge details | Cache permanently                                |
| Battery health           | Refresh approximately daily                      |
| Firmware history         | Persist and refresh occasionally                 |

Protect locally stored location data using appropriate iOS file and data-protection mechanisms.

# 24. Accessibility and UX

Requirements:

* Native iOS appearance
* Light and dark modes
* Dynamic Type
* VoiceOver labels
* Accessible chart summaries
* Appropriate color contrast
* Loading states
* Empty states
* Retry states
* Offline states
* Stale-data indicators
* Responsive layouts
* No excessive animation
* No deceptive “live” status
* No exposure of credentials or precise coordinates in errors

Support small and large iPhones. Structure the layout so iPad support can be added later.

# 25. Privacy and security

Do not include:

* Advertising
* Analytics SDKs
* Third-party tracking
* Developer-operated cloud services
* Telemetry sent to the project maintainer
* Tesla account authentication
* Tesla tokens
* Vehicle commands
* TLS bypasses
* Certificate-validation disabling
* Hardcoded credentials
* Personal API fixtures

Create:

* `PRIVACY.md`
* `SECURITY.md`
* In-app Privacy screen
* In-app About screen
* Responsible vulnerability-reporting guidance

State clearly that Tessalytics connects directly from the user’s device to the server configured by that user.

Redact from logs:

* Authorization headers
* Passwords
* VINs
* Coordinates
* Addresses
* Server query parameters containing credentials
* Vehicle names when diagnostic logging is exported

# 26. Testing

Create automated tests for:

* Generic envelope decoding
* Snake-case decoding
* Null and missing fields
* Unknown fields
* RFC 3339 dates
* Fractional-second dates
* Invalid year-zero scheduled charging dates
* Mixed units
* Bearer authentication
* Basic authentication
* Keychain behavior through an abstraction
* `401` handling
* `403` handling
* `404` handling
* `502`, `503`, and `504` handling
* Pagination
* SwiftData upserts
* Duplicate prevention
* Multi-server separation
* Multi-vehicle separation
* Offline behavior
* Analytics formulas
* Route simplification
* Status polling lifecycle
* Cancellation
* Secret redaction

Use `URLProtocol` or an equivalent injected transport for deterministic network tests.

Create at least:

* One onboarding UI smoke test
* One dashboard UI smoke test
* One drive-history UI smoke test
* One charge-history UI smoke test

Use sanitized fixtures only.

Optionally support live integration tests through ignored environment configuration:

```text
TESSALYTICS_TEST_BASE_URL
TESSALYTICS_TEST_API_TOKEN
```

Live tests must be opt-in and must never print or commit these values.

# 27. Documentation

Create a polished `README.md` containing:

* Product description
* Screenshots or screenshot placeholders
* Feature list
* Architecture overview
* Requirements
* Installation and build instructions
* How to configure a server
* How to deploy TeslaMateApi
* Direct link to TeslaMateApi
* Generic security guidance
* Privacy model
* Project status
* Contributing instructions
* Unofficial-project disclaimer
* License information

Also create:

* `CONTRIBUTING.md`
* `SECURITY.md`
* `PRIVACY.md`
* `CODE_OF_CONDUCT.md`
* `docs/architecture.md`
* `docs/backend-setup.md`
* `docs/api-compatibility.md`
* `docs/testing.md`
* `docs/app-store-checklist.md`

Do not include the user’s Cloudflare Tunnel or personal infrastructure details anywhere in the public documentation.

# 28. Build and quality workflow

Implement in this order:

1. Inspect the current TeslaMateApi source and document the actual response models.
2. Create the Xcode project.
3. Create the API and authentication abstractions.
4. Implement custom defensive decoding.
5. Implement Keychain storage.
6. Implement onboarding and connection testing.
7. Implement SwiftData models and synchronization.
8. Implement the vehicle dashboard.
9. Implement drive history.
10. Implement drive details and route simplification.
11. Implement charging history.
12. Implement charging details.
13. Implement battery health.
14. Implement software-update history.
15. Implement analytics.
16. Add accessibility.
17. Add tests.
18. Add open-source documentation.
19. Run security and privacy review.
20. Run builds and tests.
21. Fix all failures that are within scope.
22. Produce a final implementation report.

If Git is configured, commit work in logical increments. Do not push or open a pull request unless explicitly requested.

# 29. Definition of done

The work is complete when the repository contains:

* A buildable Tessalytics Xcode project
* Working onboarding
* Secure Keychain credential storage
* Typed TeslaMateApi networking
* Multiple-server support
* Multiple-vehicle support
* Vehicle dashboard
* Drive list and detail
* Route maps
* Charge list and detail
* Battery-health view
* Firmware-history view
* Analytics dashboard
* SwiftData offline cache
* Defensive decoding
* Unit conversion
* Route downsampling
* Accessibility support
* Unit tests
* UI smoke tests
* Sanitized fixtures
* Open-source README
* Backend deployment documentation linking to TeslaMateApi
* Privacy and security documentation
* MIT license, unless an existing repository decision supersedes it
* Exact build and test commands
* Clear known limitations
* A final report listing what was implemented and which tests actually passed

If macOS and Xcode are available, run the project using `xcodebuild` and fix compilation and test failures.

Do not claim the application builds or tests pass unless those commands actually completed successfully.

Make reasonable implementation decisions independently. Ask a question only when a missing decision truly blocks progress. Otherwise, record the assumption and continue implementing.
