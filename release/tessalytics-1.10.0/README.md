# Tessalytics 1.10.0 (202608251308)

TestFlight build, uploaded 2026-08-25 13:13:20 US/Pacific from `main`.
Not yet submitted for review — see **Blocked on the account holder** below.

    ASC_METADATA=release/tessalytics-1.10.0/metadata:app-store/metadata

## What changed since 1.9.5

### First run was describing the wrong thing

`saveProfile` set `phase = .ready` and then fetched. An owner with two years of
history therefore landed on a dashboard where every card showed its own
still-collecting state — "drive more to collect data" — while those very drives
were downloading. The app was describing an empty database instead of a busy one,
and the more history someone had, the more wrong it was.

There is now a `.preparing` phase with the steps and a live count as pages land.
It uses the `onProgress` callback `FleetHistorySync` has carried since it was
written — "so a first-run sync can show progress rather than appearing to hang" —
and which nothing had ever called. No percentage: the API reports no total, and a
bar with an invented denominator would be a second untruth. "Continue without
waiting" appears after six seconds so a slow server cannot trap anyone.

### iPad and Mac

iPad was already a supported destination and needed verifying rather than
building; checked on an iPad Pro 13, where the sidebar-adaptable tab view becomes
a top strip and the readable-width caps do their job. Mac is *Designed for iPad* —
the same binary on Apple Silicon. Not Catalyst: there is no Mac-specific interface
here to justify a second target, its own provisioning and its own screenshots.

### Following the Apple Account

Server profiles travel in `NSUbiquitousKeyValueStore`; credentials and Owner API
tokens travel in iCloud Keychain.

**The first attempt is worth recording, because it failed.** CloudKit-backed
SwiftData means dropping every `@Attribute(.unique)`, and nine of these ten models
dedupe cached rows by cache key. Splitting into a synced configuration and a local
one avoided that and broke something else: every test that builds its own
container over these models failed with `loadIssueModelContainer` — five failures.
Disabling the mirror under test did not help, because the split itself was the
cause, not CloudKit. Four flat fields per server do not need a database. The
key-value store has no schema, no migration and no container, and the dedupe keys
are untouched.

Credentials move from `WhenUnlockedThisDeviceOnly` to `WhenUnlocked` plus
`kSecAttrSynchronizable`, because a device-only item cannot sync by construction.
That is a real reduction in guarantee and is documented as one in `AboutView` and
`PRIVACY.md`, including how to decline it (turn off iCloud Keychain). Items
written device-only by earlier releases are migrated on first read.

## Verification

- 482 unit tests and 71 UI tests, 0 failures.
- iPad checked by hand on an iPad Pro 13; the first-run screen checked through the
  `-ui-preparing` debug flag, which exists because that screen is otherwise only
  visible in the seconds between adding a server and its history arriving.
- Archive reports `1.10.0` / `202608251308`; signed entitlements carry
  `com.apple.developer.ubiquity-kvstore-identifier`.
- With no Apple Account signed in, the app runs unchanged on the local store —
  confirmed on a simulator with no iCloud account.

## Media

`media/` carries the images and animations the README publishes on GitHub:
`dashcam.gif`, `live-driving.gif`, and the live map, night mode, live charts,
drives and charging stills.

They are **documentation, not store assets**, and cannot become store assets:
the PNGs are 600×1304 against the 1320×2868 the store requires, and an App Store
preview must be H.264 or ProRes at an exact device resolution — a GIF cannot be
uploaded as one. Producing real previews would mean screen recordings, which is
separate work.

## Screenshots

Both sets regenerated from this build with `ScreenshotCaptureTests`, which exists
precisely because "the last set went five versions stale because taking it was a
chore" — the sets in the tree dated from 20 August and predated the Efficiency and
Mileage dashboards, the dual-axis hero chart and the text trim.

- `app-store/screenshots/en-US/6.9-inch` — ten shots, 1320×2868, captured natively.
- `app-store/screenshots/en-US/12.9-inch` — ten shots, resampled to 2048×2732.
  No 12.9-inch simulator exists any more; the iPad Pro 13-inch captures at
  2064×2752, and `scripts/asc.py` targets `APP_IPAD_PRO_3GEN_129`, which expects
  2048×2732. The aspect ratios differ by 0.05 per cent, so the resample is
  imperceptible — but it is a resample, and if Apple later accepts 2064×2752 for
  this slot the native captures should be used instead.

## Blocked on the account holder

This build is **not submitted**. Four things are outside what can be done from a
terminal, and three of them would produce a bad submission if guessed:

1. **The privacy questionnaire has changed.** The previous answer was that
   credentials never leave the device. That is no longer true. The form is not in
   the App Store Connect API this repo's `scripts/asc.py` speaks; it is a web form
   on the account. Submitting against stale answers risks rejection, or worse,
   passing review while being wrong.
2. **The version is `1.10.0`,** chosen as a minor for new platforms plus a sync
   feature. It is baked into the uploaded build; changing it means another build,
   and it must be settled before submission rather than after.
3. **Mac availability is a checkbox** under Pricing and Availability, not part of
   the binary. Without it the app ships iPhone- and iPad-only whatever the build
   supports.
4. **1.6.0 still holds the editable version record** at `WAITING_FOR_REVIEW`, and
   withdrawing it forfeits its queue position the moment it happens. If it is
   close to being picked up, letting it clear may cost less time than withdrawing
   now. That is a judgement about the queue that the account holder can see and
   this cannot.
