import UserNotifications

/// Shows notifications that fire while the app is the frontmost thing on screen.
///
/// Without a delegate, iOS decides that an app already in front of the user does
/// not need to be told anything, and drops the banner and the sound on the
/// floor. `add` still succeeds, the request is still delivered, and nothing
/// appears — which is a silence that looks exactly like a feature that was never
/// wired up.
///
/// That accounted for every alert this app makes. Conditions are only evaluated
/// during a status refresh, a refresh only happens while the app is open, and
/// the immediate alerts — low battery, software update, anomalies — carry no
/// trigger, so they are delivered the instant they are scheduled, always with
/// the app in front. The test button was the clearest case: it fires one second
/// after a tap, while the reader is still looking at the settings screen that
/// tapped it, and reported "Test notification scheduled" over the top of
/// nothing.
///
/// Stateless, deliberately. `UNUserNotificationCenter.delegate` is a **weak**
/// reference, so a delegate that is only a local goes away at the end of the
/// function that set it and leaves the centre with none again — the same silence
/// back, from a line of code that looks like the fix. `shared` is what keeps it
/// alive for the life of the process.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationPresenter()

    /// What a notification arriving over the app itself is allowed to do.
    ///
    /// Named rather than inlined below so a test can state the intent without
    /// having to manufacture a `UNNotification`, which has no public
    /// initialiser.
    ///
    /// `.list` alongside `.banner`: an alert about the car that arrives while
    /// somebody happens to be looking at the car is still worth finding in
    /// Notification Centre an hour later. Without it the banner is the only copy
    /// and it disappears on its own.
    static let foregroundPresentationOptions: UNNotificationPresentationOptions = [.banner, .list, .sound]

    /// Claims the delegate. Call before the app finishes launching.
    ///
    /// Apple's requirement, and it is not academic: anything that fires during
    /// launch is presented by whatever delegate exists at that moment, so a late
    /// assignment silently loses the first notification of the session.
    static func install(on center: UNUserNotificationCenter = .current()) {
        center.delegate = shared
    }

    private override init() { super.init() }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Self.foregroundPresentationOptions
    }
}
