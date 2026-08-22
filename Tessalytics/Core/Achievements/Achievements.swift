import Foundation

/// What an achievement is measured against.
///
/// Distances are held in **kilometres** whatever the owner's units, because a
/// target that changes with a display preference is not a target: an owner who
/// switched to miles would otherwise find "1,000 driven" moving away from them.
/// The view converts for display; the arithmetic never does.
struct Achievement: Identifiable, Equatable, Sendable {
    /// The Game Center identifier. Stable forever once shipped — Game Center
    /// keys a player's progress on this string, and changing one resets everybody
    /// who had earned it.
    let id: String
    let title: String
    /// What has to happen, in the second person.
    let requirement: String
    let symbol: String
    /// The value `progress` is measured against. Always positive.
    let target: Double
    /// How the value reads on screen.
    let unit: Unit

    enum Unit: Equatable, Sendable {
        case count
        /// Kilometres, converted for display.
        case distance
        case kilowattHours
        case percent
    }
}

/// One achievement with the owner's standing against it.
struct AchievementProgress: Identifiable, Equatable, Sendable {
    let achievement: Achievement
    /// Measured in the achievement's own unit, and never above its target.
    let value: Double

    var id: String { achievement.id }
    var isEarned: Bool { value >= achievement.target }

    /// 0...100, which is the scale Game Center reports on.
    var percentComplete: Double {
        guard achievement.target > 0 else { return 0 }
        return min(max(value / achievement.target, 0), 1) * 100
    }
}

/// The figures an achievement can be judged on.
///
/// A plain value rather than a reach into `AppEnvironment`, so the catalogue can
/// be evaluated in a test without a database, a network or a Game Center account.
struct AchievementFacts: Equatable, Sendable {
    var driveCount = 0
    var chargeCount = 0
    /// Lifetime distance driven, kilometres.
    var distanceKilometres: Double = 0
    /// The longest single drive, kilometres.
    var longestDriveKilometres: Double = 0
    var energyAddedKilowattHours: Double = 0
    /// Pack health as a percentage, when it is known.
    var batteryHealthPercent: Double?
    /// Distinct days on which the car was driven.
    var daysDriven = 0
    /// The longest run of consecutive days with at least one drive.
    var longestDrivingStreak = 0
    /// Drives that began between midnight and four in the morning.
    var nightDrives = 0
    /// Distinct named places the car has been.
    var placesVisited = 0
    /// Software versions the car has run.
    var softwareVersions = 0
}

/// Everything the app can award.
///
/// Deliberately small and all derived from history the app already syncs. Nothing
/// here rewards *using the app*, which would be a reason to open it rather than a
/// fact about the car.
enum AchievementCatalogue {
    /// The prefix every identifier carries, so Game Center's namespace is
    /// unambiguous and a stray identifier is obvious.
    static let prefix = "com.echocool.Tessalytics.achievement."

    static let firstDrive = Achievement(
        id: prefix + "firstDrive",
        title: "Odometer Zero",
        requirement: "Sync your first drive",
        symbol: "car.fill",
        target: 1,
        unit: .count
    )

    static let thousandKilometres = Achievement(
        id: prefix + "distance1000",
        title: "Long Way Round",
        requirement: "Cover 1,000 km of recorded driving",
        symbol: "road.lanes",
        target: 1_000,
        unit: .distance
    )

    static let tenThousandKilometres = Achievement(
        id: prefix + "distance10000",
        title: "Continental",
        requirement: "Cover 10,000 km of recorded driving",
        symbol: "globe.europe.africa.fill",
        target: 10_000,
        unit: .distance
    )

    static let hundredThousandKilometres = Achievement(
        id: prefix + "distance100000",
        title: "Six Figures",
        requirement: "Cover 100,000 km of recorded driving",
        symbol: "infinity",
        target: 100_000,
        unit: .distance
    )

    static let longDrive = Achievement(
        id: prefix + "longDrive300",
        title: "One Sitting",
        requirement: "Complete a single drive of 300 km",
        symbol: "arrow.left.and.right",
        target: 300,
        unit: .distance
    )

    static let hundredCharges = Achievement(
        id: prefix + "charges100",
        title: "Plugged In",
        requirement: "Record 100 charging sessions",
        symbol: "bolt.fill",
        target: 100,
        unit: .count
    )

    static let megawattHour = Achievement(
        id: prefix + "energy1000",
        title: "Megawatt Hour",
        requirement: "Put 1,000 kWh into the pack",
        symbol: "bolt.batteryblock.fill",
        target: 1_000,
        unit: .kilowattHours
    )

    static let weekStreak = Achievement(
        id: prefix + "streak7",
        title: "Every Day This Week",
        requirement: "Drive on seven consecutive days",
        symbol: "calendar",
        target: 7,
        unit: .count
    )

    static let nightOwl = Achievement(
        id: prefix + "night10",
        title: "Night Shift",
        requirement: "Start ten drives between midnight and 4am",
        symbol: "moon.stars.fill",
        target: 10,
        unit: .count
    )

    static let explorer = Achievement(
        id: prefix + "places25",
        title: "Explorer",
        requirement: "Visit 25 distinct places",
        symbol: "map.fill",
        target: 25,
        unit: .count
    )

    static let updater = Achievement(
        id: prefix + "versions10",
        title: "Always Current",
        requirement: "Run ten different software versions",
        symbol: "shippingbox.fill",
        target: 10,
        unit: .count
    )

    static let wellKept = Achievement(
        id: prefix + "health90",
        title: "Well Kept",
        requirement: "Hold 90% pack health past 50,000 km",
        symbol: "heart.text.square.fill",
        target: 1,
        unit: .count
    )

    static let all: [Achievement] = [
        firstDrive, thousandKilometres, tenThousandKilometres, hundredThousandKilometres,
        longDrive, hundredCharges, megawattHour, weekStreak, nightOwl, explorer, updater, wellKept
    ]

    /// Every achievement, with the owner's standing against it, best-progressed
    /// first among the unearned so the next one to fall is at the top.
    static func evaluate(_ facts: AchievementFacts) -> [AchievementProgress] {
        all.map { AchievementProgress(achievement: $0, value: value(of: $0, from: facts)) }
    }

    /// The measured value for one achievement.
    static func value(of achievement: Achievement, from facts: AchievementFacts) -> Double {
        switch achievement.id {
        case firstDrive.id: Double(facts.driveCount)
        case thousandKilometres.id, tenThousandKilometres.id, hundredThousandKilometres.id:
            facts.distanceKilometres
        case longDrive.id: facts.longestDriveKilometres
        case hundredCharges.id: Double(facts.chargeCount)
        case megawattHour.id: facts.energyAddedKilowattHours
        case weekStreak.id: Double(facts.longestDrivingStreak)
        case nightOwl.id: Double(facts.nightDrives)
        case explorer.id: Double(facts.placesVisited)
        case updater.id: Double(facts.softwareVersions)
        case wellKept.id:
            // Both halves or nothing: 90% health at 200 km is not an achievement,
            // it is a new car.
            (facts.batteryHealthPercent ?? 0) >= 90 && facts.distanceKilometres >= 50_000 ? 1 : 0
        default: 0
        }
    }
}
