# App Store review questionnaire

Use this handoff when completing the account-level questions that are not
available through the App Store Connect API. Reconfirm every answer against the
shipping binary before submitting.

## Age rating

Completed through the API on August 19, 2026.

- Made for Kids: No
- Advertising, gambling, loot boxes, chat, social media, user-generated
  content, unrestricted web access, parental controls, age assurance, and
  health/wellness topics: No
- Violence, weapons, mature themes, profanity, sexual content, drugs/alcohol,
  simulated gambling, contests, and medical information: None
- Rating override: None

The “battery health” feature evaluates the vehicle battery. It does not provide
human medical or wellness information.

## App Privacy

Recommended answer, after the account holder confirms the shipping behavior:

**No, we do not collect data from this app.**

Rationale:

- Tessalytics has no developer-operated backend, analytics SDK, advertising,
  telemetry, or account system.
- Vehicle history is requested directly from a server chosen by the user and is
  cached in the app container.
- Credentials are stored in Keychain and are not sent to the Tessalytics
  developer.
- Optional Owner API requests go directly to the service the user explicitly
  configures.

If telemetry, crash reporting, a hosted proxy, or any third-party SDK is added,
reassess this answer before submission.

## Encryption and tracking

- Export compliance: Uses only exempt/system encryption
- `ITSAppUsesNonExemptEncryption`: No
- IDFA: No
- Tracking: No

## Content rights and audience

- Made for Kids: No
- Primary category: Utilities
- In-app purchases and subscriptions: None
- Advertising: None
- Account registration: None
- Third-party positioning: The app is an unofficial client and the store copy
  states that it is not affiliated with TeslaMate or Tesla, Inc.

For the Content Rights question, confirm that the project’s use of TeslaMate
APIs, open-source components, MapKit, user-owned vehicle data, and nominative
product names is permitted for every selected storefront. Keep the unofficial
project disclaimer visible.

## Pricing, availability, and release

Recommended for this open-source release, subject to account-holder approval:

- Price: Free
- Availability: All eligible storefronts
- License: Apple standard EULA plus the repository’s MIT license for source code
- Release: Manually release after approval

## App Review access

The reviewer needs a sanitized TeslaMateApi environment to inspect the primary
features. Enter these only in the private App Review Information fields:

- Complete contact name, phone number, and email
- Dedicated review-server URL
- Expiring Bearer credential for that server
- The instructions from `review-notes.md`

Do not provide a production server, real routes, precise locations, VINs, or an
Owner API refresh token. Direct Owner API connectivity is optional and is not
required to review the core app.
