import SwiftUI

/// What the owner watches while their history downloads for the first time.
///
/// It exists because the alternative was worse than a wait. The app used to go
/// straight to the dashboard and fetch behind it, so someone with two years of
/// drives met a screen of cards each saying its own version of "not enough data
/// yet — drive more and check back". The data was arriving at that moment. The
/// screen was describing an empty database instead of a busy one.
///
/// So the counts here are the point, not decoration: they are the evidence that
/// something is happening. There is no percentage, because the API reports no
/// total and a bar with an invented denominator would be a second untruth.
struct PreparingView: View {
    let progress: AppEnvironment.PreparationProgress
    let serverName: String?
    /// Lets the owner leave before the sync finishes.
    var onSkip: () -> Void = {}

    /// The wait before the way out is offered.
    ///
    /// A first-run screen with no exit is a trap, and on a server that is slow
    /// or half-reachable this one could otherwise hold someone indefinitely. It
    /// is not offered immediately because on a fast server the whole sync is
    /// over in less time than it takes to read the button.
    private static let skipAfter: Duration = .seconds(6)

    @State private var canSkip = false

    private var steps: [AppEnvironment.PreparationProgress.Step] {
        [.vehicles, .status, .history, .battery, .finishing]
    }

    private func state(of step: AppEnvironment.PreparationProgress.Step) -> StepState {
        guard let current = steps.firstIndex(of: progress.step),
              let index = steps.firstIndex(of: step) else { return .waiting }
        if index < current { return .done }
        return index == current ? .running : .waiting
    }

    var body: some View {
        TessalyticsScreen {
            VStack(spacing: 28) {
                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    // Not a car with a warning triangle on it, which is what
                    // the first choice here turned out to look like at a glance.
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(TessalyticsTheme.accent)
                        .symbolRenderingMode(.hierarchical)
                        .accessibilityHidden(true)
                    Text("Getting your history")
                        .font(.title2.bold())
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(steps, id: \.self) { step in
                            StepRow(
                                title: step.title,
                                detail: detail(for: step),
                                state: state(of: step)
                            )
                        }
                    }
                }
                .tessalyticsReadableWidth(420)

                Text("This happens once. Later launches only fetch what is new.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)

                if canSkip {
                    Button("Continue without waiting", action: onSkip)
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("skip-preparing")
                        .accessibilityHint("Opens the app now. The rest downloads in the background.")
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .tessalyticsScreenPadding()
        }
        .task {
            try? await Task.sleep(for: Self.skipAfter)
            withAnimation { canSkip = true }
        }
        .accessibilityIdentifier("preparing-screen")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Getting your history")
        .accessibilityValue(spokenProgress)
    }

    private var subtitle: String {
        guard let serverName = serverName?.nilIfEmpty else { return "Reading your TeslaMate server." }
        return AppText.format("Reading %@.", serverName)
    }

    /// The counts, on the row they belong to.
    private func detail(for step: AppEnvironment.PreparationProgress.Step) -> String? {
        guard step == .history, progress.isCountingHistory else { return nil }
        guard progress.drives + progress.charges > 0 else { return "Starting" }
        return AppText.format(
            "%1$@ drives · %2$@ charges",
            "\(progress.drives)", "\(progress.charges)"
        )
    }

    private var spokenProgress: String {
        var parts = [progress.step.title]
        if progress.isCountingHistory, progress.drives + progress.charges > 0 {
            parts.append("\(progress.drives) drives and \(progress.charges) charges so far")
        }
        return parts.joined(separator: ", ")
    }
}

private enum StepState { case waiting, running, done }

private struct StepRow: View {
    @Environment(\.locale) private var locale
    let title: String
    let detail: String?
    let state: StepState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            marker
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(locale.appString(title))
                    .font(.subheadline.weight(state == .running ? .semibold : .regular))
                    .foregroundStyle(state == .waiting ? .secondary : .primary)
                if let detail {
                    Text(locale.appString(detail))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        // The counter changes several times a second on a large
                        // history; without this the row jitters as digits land.
                        .contentTransition(.numericText())
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var marker: some View {
        switch state {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(TessalyticsTheme.positive)
        case .running:
            ProgressView().controlSize(.small)
        case .waiting:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        }
    }
}
