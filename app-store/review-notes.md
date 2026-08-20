# App Review notes

The text actually pasted into App Store Connect lives in
`release/tessalytics-1.2.1/metadata/review_notes.txt` and is pushed by
`scripts/asc.py push-review-notes`. It opens with demo mode, because a reviewer
has no TeslaMate server and cannot get past onboarding without one.

## Preferred path: demo mode, no server needed

1. On the first onboarding screen, tap **Explore Demo**. That is the only step.
2. Tessalytics generates about two months of sample drives, charging sessions,
   routes, analytics, battery trends, and forecasts on the device.
3. It needs no TeslaMate server, no Tesla account, no credentials, and no
   network connection, is labeled as demo data throughout, and never enables
   vehicle commands.
4. Status, Activity, Analysis, and Settings are all fully populated.

Leave demo mode with **Settings → Leave demo** or **Settings → Connect a real
server**; saved server profiles are preserved.

## Fallback: a real server connection

Only needed if a reviewer explicitly asks to see a live connection.

## App Review connection

- Base URL: `[ADD DEDICATED REVIEW SERVER URL IN APP STORE CONNECT]`
- Authentication method: Bearer token
- Bearer token: `[ADD EXPIRING REVIEW TOKEN IN APP STORE CONNECT]`

Do not commit these values to the repository. Use a sanitized, read-only review server without personal routes, addresses, VINs, or precise locations whenever possible.

## Review steps

1. Launch the app and tap **Configure server**.
2. Enter `App Review` as the profile name.
3. Enter the review server URL above.
4. Choose **Bearer token** and enter the review token.
5. Tap **Test Connection**, then **Save Securely** after all three checks pass.
6. The Status tab shows current or last-reported vehicle data.
7. Activity contains drive and charging history; Analysis contains charts, forecasts, and battery estimates.
8. Settings contains privacy information, software history, notifications, and the optional direct connection.

No purchase, subscription, account registration, advertising, or tracking is present.

The optional Owner API connection is not required for the primary TeslaMate features. It accepts a token pair generated outside the app; Tessalytics never requests a Tesla password. If direct controls are reviewed, every command first presents an in-app confirmation and then requires Face ID or the device passcode. The Owner API is unofficial and is clearly labeled optional.

Tessalytics communicates only with endpoints entered by the reviewer and, when explicitly configured, the unofficial Owner API. Historical data is cached locally for offline use. Credentials are stored in Keychain.

## Review contact placeholders

- First name: `[REQUIRED]`
- Last name: `[REQUIRED]`
- Phone: `[REQUIRED]`
- Email: `[REQUIRED]`
