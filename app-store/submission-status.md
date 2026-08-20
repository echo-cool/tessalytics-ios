# App Store Connect handoff

Status captured on August 19, 2026 for app `6803221525`.

## Completed through the App Store Connect API

- App Store version: 1.1.0 (`PREPARE_FOR_SUBMISSION`)
- Selected build: 5 (`VALID`, App Store eligible)
- Primary category: Utilities
- English (U.S.) subtitle, description, promotional text, and keywords
- Five 6.9-inch iPhone screenshots, all processed successfully
- Age-rating questionnaire completed with no applicable restricted content
- Exempt-encryption declaration confirmed by the processed build
- English (U.S.) TestFlight beta description, feedback email, and build 5 testing notes
- TestFlight 1.0.3 build `202608191804` is `VALID`, in Internal beta testing, and has current Demo Mode testing notes
- Copyright: 2026 Echo Cool

The source copy for these fields is kept in `metadata/en-US.md` and
`metadata/en-US.json`.

The package also includes reusable What's New copy. App Store Connect does not
accept that field for this initial store version, so it remains local for a
future update.

## Required before review submission

- Make the open-source repository public, then verify the support, marketing,
  privacy-policy, security-policy, and license links without authentication.
- Add a support URL and privacy-policy URL in App Store Connect after those
  pages are public.
- Add the App Review contact name, phone number, and email address.
- Put a dedicated sanitized review-server URL and expiring review credential in
  the private App Review notes. Never add either value to this repository.
- Complete App Privacy, content-rights, availability, pricing, and any
  applicable trader-status questions using `review-questionnaire.md`.
- Review the final product page and submit manually.

No review submission was started by the API preparation work.

The App Store version remains 1.1.0 with build 5 selected. Uploading the separate
1.0.3 TestFlight train did not change the prepared App Store review version.
