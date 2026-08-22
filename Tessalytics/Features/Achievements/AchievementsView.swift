import SwiftUI
#if canImport(GameKit)
import GameKit
#endif

/// What the car has earned.
///
/// Works whether or not Game Center is available: every achievement is a fact
/// about the driving, computed from the history already on the device. Game
/// Center is where they are *recorded* — a second place they exist, not the place
/// they come from — so a player who is signed out sees the same list.
struct AchievementsView: View {
    @Environment(AppEnvironment.self) private var environment

    private var progress: [AchievementProgress] { environment.achievements }
    private var earned: [AchievementProgress] { progress.filter(\.isEarned) }
    /// Closest first, so the next one to fall is at the top.
    private var remaining: [AchievementProgress] {
        progress.filter { !$0.isEarned }.sorted { $0.percentComplete > $1.percentComplete }
    }

    var body: some View {
        TessalyticsScreen {
            ScrollView {
                LazyVStack(spacing: TessalyticsLayout.stackSpacing) {
                    summary
                    gameCenterCard
                    if !remaining.isEmpty {
                        SectionCard("In progress", symbol: "figure.walk", tint: TessalyticsTheme.accent) {
                            VStack(spacing: 14) {
                                ForEach(remaining) { AchievementRow(progress: $0, units: environment.statusUnits) }
                            }
                        }
                    }
                    if !earned.isEmpty {
                        SectionCard("Earned", symbol: "rosette", tint: TessalyticsTheme.positive) {
                            VStack(spacing: 14) {
                                ForEach(earned) { AchievementRow(progress: $0, units: environment.statusUnits) }
                            }
                        }
                    }
                }
                .tessalyticsScreenPadding()
                .tessalyticsReadableWidth()
            }
        }
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("achievements-screen")
    }

    private var summary: some View {
        SectionCard(
            "\(earned.count) of \(progress.count)",
            subtitle: environment.fleet.isComplete
                ? "Judged against your whole synced history"
                : "Judged against what has synced so far",
            symbol: "trophy.fill",
            tint: TessalyticsTheme.warning
        ) {
            ProgressView(value: Double(earned.count), total: Double(max(progress.count, 1)))
                .tint(TessalyticsTheme.warning)
                .accessibilityLabel("Achievements earned")
                .accessibilityValue("\(earned.count) of \(progress.count)")
        }
    }

    @ViewBuilder private var gameCenterCard: some View {
        switch environment.gameCenter.state {
        case .authenticated(let name):
            SectionCard("Game Center", subtitle: name, symbol: "gamecontroller.fill", tint: TessalyticsTheme.positive) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Progress is recorded to Game Center as it changes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let error = environment.gameCenter.lastReportError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(TessalyticsTheme.warning)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .unavailable(let reason):
            SectionCard("Game Center", symbol: "gamecontroller", tint: TessalyticsTheme.steel) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                    Text("The list below is computed on this device and does not need it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if environment.gameCenter.canPresentSignIn {
                        Button("Sign in to Game Center") { environment.gameCenter.presentSignIn() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("game-center-sign-in")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .unknown, .authenticating:
            EmptyView()
        }
    }
}

/// One achievement, with how far along it is.
private struct AchievementRow: View {
    let progress: AchievementProgress
    let units: UnitsDTO?

    private var achievement: Achievement { progress.achievement }
    private var tint: Color { progress.isEarned ? TessalyticsTheme.positive : TessalyticsTheme.steel }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: progress.isEarned ? achievement.symbol : "lock.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: 11))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(achievement.title).font(.subheadline.weight(.semibold))
                    if progress.isEarned {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(TessalyticsTheme.positive)
                            .accessibilityHidden(true)
                    }
                }
                Text(achievement.requirement)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !progress.isEarned {
                    ProgressView(value: progress.percentComplete, total: 100)
                        .tint(TessalyticsTheme.accent)
                    Text(standing)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(achievement.title)
        .accessibilityValue(progress.isEarned ? "Earned. \(achievement.requirement)" : standing)
        .accessibilityIdentifier("achievement-\(achievement.id)")
    }

    /// "620 of 1,000 km", in the owner's own units.
    private var standing: String {
        let resolved = units ?? .metricDefaults
        switch achievement.unit {
        case .distance:
            // Targets are held in kilometres so they cannot move with a display
            // preference; this is the one place they are converted back.
            let factor = 1 / AchievementFactsBuilder.kilometreFactor(for: resolved)
            return "\(format(progress.value * factor)) of \(format(achievement.target * factor)) \(resolved.lengthSymbol)"
        case .kilowattHours:
            return "\(format(progress.value)) of \(format(achievement.target)) kWh"
        case .percent:
            return "\(format(progress.value))% of \(format(achievement.target))%"
        case .count:
            return "\(format(progress.value)) of \(format(achievement.target))"
        }
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)).grouping(.automatic))
    }
}
