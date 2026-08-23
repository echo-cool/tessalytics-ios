# Game Center achievement artwork

Twelve 512×512 badges, one per achievement in `AchievementCatalogue`. Each file is
named for the last component of its vendor identifier, so
`distance10000.png` belongs to `com.echocool.Tessalytics.achievement.distance10000`.

Regenerate them with:

```sh
swift scripts/game-center-badges.swift app-store/game-center
```

They are drawn rather than designed: the same SF Symbol the app shows for that
achievement, on the app's own palette, filled white on a gradient. Colour follows
category so the twelve read as a set — red for distance, green for energy and
health, amber for time and place, steel for the car's own record.

Apple requires 512×512, RGB, **no alpha channel**. The generator uses a
`noneSkipLast` CoreGraphics context so the PNG carries none; an `NSBitmapImageRep`
at 24 bits per pixel silently yields no drawing context at all, which is worth
knowing before spending an afternoon on twelve black squares.

## Uploading

The image hangs off the *localization*, not the achievement:

    POST gameCenterAchievementImages   → relationship to gameCenterAchievementLocalization
    PUT  the bytes to uploadOperations
    PATCH gameCenterAchievementImages/{id} {"uploaded": true}

The commit takes `uploaded` **only**. Unlike `appScreenshots`, this resource has
no `sourceFileChecksum` attribute and rejects the whole request with a 409 if one
is sent — the bytes are already uploaded by then, so the fix is to re-PATCH rather
than to start again.
