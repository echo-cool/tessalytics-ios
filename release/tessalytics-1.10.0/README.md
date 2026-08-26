# Tessalytics 1.10.0 (202608251308)

**Superseded by build 202608251806.** That build carries everything below plus
the multi-column iPad dashboard, and is the one in review.

Build `202608251308` was uploaded 2026-08-25 13:13:20, submitted, then withdrawn
so the board could ship in this submission rather than the next one. Build
`202608251806` was uploaded 18:11:08 from `main` at `4d66902`, processed `VALID`,
and submitted as review submission `5c5e76a1-1ad5-41ea-b370-27baacea8485`. Build
resource `6b7a58c4-5188-4a1f-8a91-3726b92c6e8f`, TestFlight expiry 2026-11-23,
export compliance exempt, minimum iOS 18.0.

The marketing version did not move: 1.10.0 has never been released, so a new
build replaces the binary on the same version record rather than opening a new
one. Withdrawing forfeited the queue position both times.

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

## The iPad board (build 202608251806)

The dashboard was a single 760-point column. On an iPad Pro 13 in landscape the
sidebar takes about 280 points and leaves 1,072, so a third of the usable width
was margin. It is now three columns in landscape, two in portrait, one on a
phone, and the cards can be rearranged and stay where they are put.

The column step is at 1,050 points because that sits between the two widths this
actually runs at — 1,008 portrait, 1,072 landscape — so turning the iPad gains a
column instead of stretching cards. A first attempt used 1,150 and never reached
three: a guess that had not accounted for the sidebar.

Dragging did not work at first either. The cards' gestures are suppressed while
arranging so a chart cannot scrub under the finger, but `allowsHitTesting(false)`
was on the same view as `draggable` and disabled the drag with it — the board
scrolled instead of moving the card. The content is now inert inside a container
that stays live.

Arranging is an explicit mode rather than always-on dragging, because these cards
hold charts that scrub and maps that pan. Five cards are pinned: the hero, the
still-collecting notice, both live sections, the status fallback. Reset is in the
Arrange button's context menu.

The iPad screenshots were re-taken against this build. The set pushed with
202608251308 showed the old single narrow column and would have misrepresented
the app.

## Still outside what a terminal can do

The submission is in, but two of these remain unset and affect it:

1. **The privacy questionnaire needs nothing** — an earlier claim in this kit
   that it did was wrong and is corrected here. Verified: no location APIs, no
   third-party SDKs, an empty `NSPrivacyCollectedDataTypes`, and Apple's
   definition of "collect" turns on the developer having access, which for the
   user's own iCloud is not the case. What *did* need fixing was the policy page
   the listing links to, `tessalytics.echo.cool/privacy`, which still promised
   tokens never leave the device. That page is corrected in the tree but **not
   deployed** — a Cloudflare publish, and the live page currently contradicts the
   build in review.
2. **The version is `1.10.0`,** chosen as a minor for new platforms plus a sync
   feature, and now submitted as such.
3. **Mac availability is a checkbox** under Pricing and Availability, not part of
   the binary. Without it the app ships iPhone- and iPad-only whatever the build
   supports.
4. **1.6.0 was withdrawn** and its record renamed to 1.10.0. Three withdrawals
   happened in total on 25 August — 1.6.0, then 1.10.0 twice — each forfeiting
   the queue position. Worth weighing before the next one.
