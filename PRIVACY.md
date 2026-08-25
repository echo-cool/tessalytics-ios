# Privacy

Tessalytics is designed around direct, user-controlled connections.

## Data flow

The app connects directly from the user’s iPhone to the TeslaMateApi server configured by that user and, when the user enables it, Tesla’s Owner API. The Tessalytics project does not operate a relay, account system, analytics service, telemetry endpoint, or cloud backend.

## Credentials

TeslaMate bearer tokens, HTTP Basic credentials, and optional Owner API access and refresh tokens are stored in Keychain items marked `kSecAttrSynchronizable` with `kSecAttrAccessibleWhenUnlocked`. They are therefore available only while a device is unlocked, and they synchronise through iCloud Keychain to the other devices signed in to the same Apple Account.

iCloud Keychain is end-to-end encrypted: the keys derive from the user's own devices and passcode, and Apple cannot read the contents. Before version 1.9.6 these items were `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and did not leave the device; that guarantee has been deliberately traded for synchronisation, so that a user with more than one device does not have to configure each separately. A user who does not want it can turn off iCloud Keychain in iOS Settings, in which case the items remain local to the device.

Credentials are not stored in SwiftData, `UserDefaults`, `Info.plist`, source code, or diagnostics, and are not placed in the app's iCloud key-value store.

Owner API access-token refresh happens directly between the iPhone and Tesla. Tessalytics saves the replacement access and refresh tokens returned by Tesla before continuing. The app does not request or store a Tesla account password.

## Synchronised data

The server profiles a user configures — the profile name, the server address, the authentication method, and whether insecure HTTP was permitted for that profile — are written to the app's iCloud key-value store and synchronise to the other devices signed in to the same Apple Account. That store is private to the app and to that account. Credentials are never written to it; they travel through iCloud Keychain, which is end-to-end encrypted.

Cached vehicle history is not synchronised. Drives, charges, routes, battery observations and firmware history remain on the device that fetched them, and are re-fetched from the user's own server on another device.

## Locally stored data

Tessalytics may cache vehicle metadata, drive and charging history, detailed routes and samples, battery-health observations, firmware history, and synchronization metadata for offline access. Records are partitioned by server profile and vehicle. A status snapshot is never presented as current after a failed refresh; offline data is labeled stale.

The app relies on iOS app-container and data-protection safeguards. Removing the app removes its local database. Credentials may be removed by deleting their server profile or the app.

## Data not collected

Tessalytics contains no advertising, third-party tracking, analytics SDK, or maintainer telemetry. Owner API tokens and vehicle data are not sent to the Tessalytics maintainers.

When the optional Owner API connection is enabled, Tessalytics can send user-initiated lock, climate, charging, and trunk commands directly to Tesla. Each command requires an in-app confirmation and successful Face ID or device-passcode authentication. Tessalytics does not automatically wake a sleeping vehicle or send commands in the background.

## Logs

Application diagnostics must not include authorization headers, passwords, tokens, VINs, coordinates, addresses, or vehicle names. The redaction utility is tested. Do not attach unreviewed device or reverse-proxy logs to public issues.
