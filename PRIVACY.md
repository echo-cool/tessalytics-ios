# Privacy

Tessalytics is designed around direct, user-controlled connections.

## Data flow

The app connects directly from the user’s iPhone to the TeslaMateApi server configured by that user and, when the user enables it, Tesla’s Owner API. The Tessalytics project does not operate a relay, account system, analytics service, telemetry endpoint, or cloud backend.

## Credentials

TeslaMate bearer tokens and HTTP Basic credentials are stored only in iOS Keychain with `kSecAttrAccessibleAfterFirstUnlock`. Optional Owner API access and refresh tokens are stored in a separate Keychain item with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, so they are available only while the device is unlocked and do not migrate to another device. Credentials are not stored in SwiftData, `UserDefaults`, `Info.plist`, source code, or diagnostics.

Owner API access-token refresh happens directly between the iPhone and Tesla. Tessalytics saves the replacement access and refresh tokens returned by Tesla before continuing. The app does not request or store a Tesla account password.

## Locally stored data

Tessalytics may cache vehicle metadata, drive and charging history, detailed routes and samples, battery-health observations, firmware history, and synchronization metadata for offline access. Records are partitioned by server profile and vehicle. A status snapshot is never presented as current after a failed refresh; offline data is labeled stale.

The app relies on iOS app-container and data-protection safeguards. Removing the app removes its local database. Credentials may be removed by deleting their server profile or the app.

## Data not collected

Tessalytics contains no advertising, third-party tracking, analytics SDK, or maintainer telemetry. Owner API tokens and vehicle data are not sent to the Tessalytics maintainers.

When the optional Owner API connection is enabled, Tessalytics can send user-initiated lock, climate, charging, and trunk commands directly to Tesla. Each command requires an in-app confirmation and successful Face ID or device-passcode authentication. Tessalytics does not automatically wake a sleeping vehicle or send commands in the background.

## Logs

Application diagnostics must not include authorization headers, passwords, tokens, VINs, coordinates, addresses, or vehicle names. The redaction utility is tested. Do not attach unreviewed device or reverse-proxy logs to public issues.
