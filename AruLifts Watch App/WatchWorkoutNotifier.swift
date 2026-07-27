import Foundation
import OSLog
import UserNotifications
import WatchKit

/// Pulls the user into a workout that was started on the iPhone.
///
/// HealthKit launches or wakes the watchOS app, WatchConnectivity supplies the
/// durable AruLifts session, and this notification is the optional final
/// presentation step. Tapping it opens the already-persisted live session.
@MainActor
enum WatchWorkoutNotifier {
    /// Reusing one identifier means a second arrival replaces the first banner
    /// rather than stacking, and `clear()` only has to know about one request.
    private static let identifier = "arulifts.workout.ready"
    private static let logger = Logger(
        subsystem: "com.arulifts.app.watchkitapp",
        category: "Notifications"
    )

    /// Requests notification permission only while the app is visibly active.
    /// A HealthKit background wake must never be the moment that a permission
    /// sheet is attempted.
    static func requestAuthorizationIfNeeded() async {
        guard WKApplication.shared().applicationState == .active else {
            logger.info("Skipping notification authorization outside foreground")
            return
        }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            logger.info(
                "Notification authorization already resolved: \(String(describing: settings.authorizationStatus), privacy: .public)"
            )
            return
        }
        do {
            let granted = try await center.requestAuthorization(
                options: [.alert, .sound]
            )
            logger.info("Notification authorization granted: \(granted)")
        } catch {
            logger.error(
                "Notification authorization failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Announces an already-persisted workout that appeared while the user
    /// wasn't looking. This is presentation only; HealthKit performs the wake.
    static func workoutDidArrive(named name: String, sessionID: UUID) async {
        // Already on screen — a banner over the live workout is pure noise.
        guard WKApplication.shared().applicationState != .active else {
            logger.info(
                "Workout \(sessionID.uuidString, privacy: .public) is already onscreen"
            )
            return
        }

        let content = UNMutableNotificationContent()
        content.title = name.isEmpty ? "Workout ready" : name
        content.body = "Started on iPhone — tap to log your sets here."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil    // nil trigger delivers immediately
        )

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .denied:
            logger.notice(
                "Notification denied for workout \(sessionID.uuidString, privacy: .public); manual open remains available"
            )
            return
        case .notDetermined:
            logger.notice(
                "Notification permission not determined for workout \(sessionID.uuidString, privacy: .public); foreground authorization required"
            )
            return
        @unknown default:
            logger.notice("Unknown notification authorization status")
            return
        }

        do {
            try await center.add(request)
            logger.info(
                "Scheduled workout notification \(sessionID.uuidString, privacy: .public)"
            )
        } catch {
            logger.error(
                "Failed to schedule workout notification \(sessionID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Drops the banner once the user has arrived or the workout is over.
    /// watchOS clears it automatically when the notification itself is tapped;
    /// this covers the other routes in (opening from the Dock, or the workout
    /// ending on the phone before the user ever looked).
    static func clear() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
