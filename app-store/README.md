# App Store submission assets

This directory contains public, sanitized assets and English (U.S.) metadata for Tessalytics.

## Screenshot set

`screenshots/en-US/6.9-inch/` contains five portrait JPEG screenshots captured from generated demo data on an iPhone 17 Pro Max simulator.

- Dimensions: 1320 × 2868 pixels
- Color: RGB JPEG with no alpha channel
- Locale: English (U.S.)
- Display target: 6.9-inch iPhone (`APP_IPHONE_67` in the App Store Connect API)
- Order: Status, Analytics, Forecasts, Battery Health, Onboarding

Apple accepts one to ten screenshots. The highest-resolution iPhone set can be scaled for smaller displays when the interface is shared. Check Apple's current [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) before uploading a future release.

## Metadata

- `metadata/en-US.md` is the human-readable submission copy.
- `metadata/en-US.json` is the machine-readable source used for App Store Connect API updates.
- `metadata/testflight-en-US.md` contains the public-safe beta description and per-build testing focus.
- `review-notes.md` contains reviewer instructions and clearly marked placeholders for private review credentials and contact information.
- `review-questionnaire.md` prepares the App Privacy, age-rating, encryption, content-rights, pricing, and availability answers.
- `submission-status.md` records the current App Store Connect handoff and remaining private/account-level work.

Do not commit App Store Connect private keys, review credentials, server URLs, vehicle identifiers, routes, addresses, or Owner API tokens.

## Before submitting for review

1. Confirm the version number matches the selected build.
2. Confirm every screenshot still represents the shipping UI.
3. Publish `PRIVACY.md` at the privacy-policy URL.
4. Add App Review contact information.
5. Provide a dedicated sanitized TeslaMateApi review server and expiring credential through App Store Connect—not this repository.
6. Complete the age-rating and app-privacy questionnaires.
7. Select the valid build, verify export compliance, and submit manually after a final review.
