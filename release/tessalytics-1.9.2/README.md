# Tessalytics 1.9.2 (202608241143)

TestFlight build. 1.6.0 still holds the editable version record
(`WAITING_FOR_REVIEW`), so this train carries beta notes only — there is nowhere
for store copy to land until that submission clears.

    ASC_METADATA=release/tessalytics-1.9.2/metadata:app-store/metadata

Uploaded 2026-08-24 11:47 from `main` at `2bfa743`, archived Release,
`destination: upload`. No `metadata/` directory: nothing in the store copy
changed, and `scripts/asc.py` skips any field whose file is absent rather than
overwriting a good description with a stale one.

## What changed since 1.9.1

Two fixes, both found by reading the console rather than by a failing test —
worth noting, because neither would have been caught by the suite as it stands.

### The hero card's navigation destination sat in a lazy container

`DashboardView` attached `.navigationDestination(item:)` to the vehicle hero
card, which is built inside a lazy container. SwiftUI logs this and says plainly
that it "will be ignored in a future release" — meaning the four pushes off the
hero card (battery health, drives, tyres, vehicle settings) would have stopped
working on some future iOS, silently, in a build that had shipped months
earlier. The modifier now sits on the screen, where the navigation stack can
always see it.

### Intelligence notifications were dropped rather than presented

Fixed in `be13296`.

## Not in this build

The optional Supabase account and config sync is **not** here. It lives on
`feature/supabase-account-sync`, rebased onto this commit's parent, and is
waiting on three things that are not code:

- `0001_account_sync.sql` and `0002_avatars.sql` run against the project
- the `delete-account` Edge Function deployed
- Google's client id added to the provider's Authorized Client IDs

Until those land, a sign-in succeeds and the first sync fails — so the branch
stays off the train. The server half is now its own repository at
`../Tessalytics-Supabase`.

## Verification

- 482 unit tests, 0 failures, on the archived commit.
- `xcodegen generate` produces no working-tree drift, so the committed project
  file matches `project.yml`.
- Archive reports `CFBundleShortVersionString 1.9.2` /
  `CFBundleVersion 202608241143`; `manageAppVersionAndBuildNumber` is `false` in
  the export options so Xcode cannot substitute its own number on the way out.

## Next

Beta notes only. When 1.6.0 clears review the editable record frees up, and the
store copy in `app-store/metadata` can be pushed against whichever train is
current — see `scripts/asc.py prepare-version` and the note in the 1.2.1 kit
about withdrawing before preparing a new one.
