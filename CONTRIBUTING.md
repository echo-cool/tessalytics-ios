# Contributing

Thank you for helping Tessalytics become a dependable community client.

1. Discuss large behavior or persistence changes in an issue first.
2. Create a focused branch and keep commits understandable.
3. Keep vehicle control narrowly scoped: require explicit confirmation and device-owner authentication, never wake vehicles automatically, and never add background or logging controls.
4. Never commit server URLs, credentials, VINs, coordinates, addresses, vehicle names, or personal infrastructure details.
5. Add deterministic tests and sanitized fixtures for changed decoding, persistence, synchronization, or calculations.
6. Run the build and test commands in `docs/testing.md`.
7. Update public documentation and accessibility labels when behavior changes.

Code should follow Swift 6 concurrency checking, native Apple API conventions, Dynamic Type, VoiceOver support, and the existing feature-oriented architecture. New third-party dependencies require a documented, substantial benefit.

By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md) and license your contribution under AGPL-3.0-or-later.
