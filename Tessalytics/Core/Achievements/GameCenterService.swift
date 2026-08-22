import Foundation
import Observation
#if canImport(GameKit)
import GameKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Game Center, held at arm's length.
///
/// Two rules shape this. Game Center may simply not be available — the player is
/// signed out, the region does not offer it, the identifiers have not been
/// created in App Store Connect yet — and none of that may stop the achievements
/// screen from working, because the achievements are facts about the car and the
/// app already knows them. And nothing is reported that has not moved: progress
/// is recomputed on every history sync, and re-sending an unchanged 40% on each
/// one is traffic that buys nothing.
@MainActor
@Observable
final class GameCenterService {
    enum State: Equatable, Sendable {
        case unknown
        case authenticating
        case authenticated(playerName: String)
        /// Game Center is not available, with the reason where there is one.
        case unavailable(String)

        var isAuthenticated: Bool {
            if case .authenticated = self { return true }
            return false
        }
    }

    private(set) var state: State = .unknown
    /// The last failure from reporting, which is usually "this identifier does
    /// not exist in App Store Connect yet".
    private(set) var lastReportError: String?
    /// What has already been sent, so an unchanged figure is not sent again.
    private var reported: [String: Double] = [:]

    /// Progress has to move by this much before it is worth another round trip.
    static let reportingThreshold: Double = 0.5

    init() {}

    /// Signs the player in, if they have an account.
    ///
    /// Called once, at launch. Game Center's handler can be invoked more than
    /// once over a session — the player can sign in and out from Settings — so
    /// this keeps the state current rather than assuming a single answer.
    func authenticate() {
        #if canImport(GameKit)
        guard case .unknown = state else { return }
        state = .authenticating
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                guard let self else { return }
                if let viewController {
                    // Game Center wants to show its sign-in sheet. Presenting it
                    // unbidden over a car's live telemetry would be rude, so it
                    // is offered from the achievements screen instead.
                    self.pendingSignIn = viewController
                    self.state = .unavailable("Sign in to Game Center to record achievements.")
                    return
                }
                if let error {
                    self.state = .unavailable(error.localizedDescription)
                    return
                }
                guard GKLocalPlayer.local.isAuthenticated else {
                    self.state = .unavailable("Game Center is not signed in on this device.")
                    return
                }
                self.pendingSignIn = nil
                self.state = .authenticated(playerName: GKLocalPlayer.local.alias)
            }
        }
        #else
        state = .unavailable("Game Center is not available on this platform.")
        #endif
    }

    #if canImport(GameKit)
    /// Game Center's own sign-in screen, held until the owner asks for it.
    private(set) var pendingSignIn: UIViewController?

    /// Shows the sign-in sheet Game Center handed us.
    func presentSignIn() {
        guard let pendingSignIn, let presenter = Self.topViewController() else { return }
        presenter.present(pendingSignIn, animated: true)
        self.pendingSignIn = nil
    }

    var canPresentSignIn: Bool { pendingSignIn != nil }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
    #else
    var canPresentSignIn: Bool { false }
    func presentSignIn() {}
    #endif

    /// Sends progress that has actually changed.
    func report(_ progress: [AchievementProgress]) async {
        #if canImport(GameKit)
        guard state.isAuthenticated else { return }
        let changed = progress.filter { entry in
            let previous = reported[entry.id]
            guard let previous else { return entry.percentComplete > 0 }
            return entry.percentComplete - previous >= Self.reportingThreshold
        }
        guard !changed.isEmpty else { return }

        let achievements = changed.map { entry -> GKAchievement in
            let achievement = GKAchievement(identifier: entry.id)
            achievement.percentComplete = entry.percentComplete
            // The banner is Game Center's, and it only fires on the transition to
            // 100%, so this costs nothing on a partial report.
            achievement.showsCompletionBanner = true
            return achievement
        }
        do {
            try await GKAchievement.report(achievements)
            for entry in changed { reported[entry.id] = entry.percentComplete }
            lastReportError = nil
        } catch {
            // Almost always "an achievement with this identifier does not exist",
            // which means App Store Connect has not been told about it yet. Worth
            // surfacing on the debug screen and worth ignoring everywhere else.
            lastReportError = error.localizedDescription
        }
        #endif
    }

    /// Forgets what has been sent, so the next report resends everything.
    func resetReportingCache() { reported = [:] }
}
