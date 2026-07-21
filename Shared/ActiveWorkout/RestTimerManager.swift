import Foundation
import Combine
import UserNotifications

#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

/// A countdown rest timer that survives backgrounding via a scheduled local
/// notification and fires a haptic when it completes. Used after each set.
@MainActor
final class RestTimerManager: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var totalSeconds: Int = 0
    @Published private(set) var secondsRemaining: Int = 0

    private(set) var endDate: Date?
    private var ticker: Timer?
    private let notificationID = "aru.rest.timer"
    var onStateChange: (() -> Void)?

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalSeconds - secondsRemaining) / Double(totalSeconds)
    }

    var formattedRemaining: String {
        let s = max(0, secondsRemaining)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    nonisolated static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func start(seconds: Int, alertsEnabled: Bool = true) {
        guard seconds > 0 else { return }
        totalSeconds = seconds
        secondsRemaining = seconds
        endDate = Date().addingTimeInterval(TimeInterval(seconds))
        isRunning = true
        startTicker()
        if alertsEnabled { scheduleNotification(after: seconds) }
        onStateChange?()
    }

    func add(seconds: Int) {
        guard isRunning, let end = endDate else { return }
        let newEnd = end.addingTimeInterval(TimeInterval(seconds))
        endDate = newEnd
        totalSeconds = max(totalSeconds + seconds, 1)
        cancelNotification()
        scheduleNotification(after: Int(newEnd.timeIntervalSinceNow))
        tick()
        onStateChange?()
    }

    func skip() {
        finish(playHaptic: false)
    }

    func stop() {
        isRunning = false
        endDate = nil
        secondsRemaining = 0
        ticker?.invalidate()
        ticker = nil
        cancelNotification()
        onStateChange?()
    }

    func sync(endDate: Date, totalSeconds: Int) {
        self.totalSeconds = totalSeconds
        self.endDate = endDate
        self.secondsRemaining = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
        self.isRunning = true
        startTicker()
    }

    // MARK: - Ticking

    private func startTicker() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard let end = endDate else { return }
        let remaining = Int(ceil(end.timeIntervalSinceNow))
        secondsRemaining = max(0, remaining)
        if remaining <= 0 {
            finish(playHaptic: true)
        }
    }

    private func finish(playHaptic: Bool) {
        isRunning = false
        endDate = nil
        secondsRemaining = 0
        ticker?.invalidate()
        ticker = nil
        cancelNotification()
        if playHaptic { playCompletionHaptic() }
        onStateChange?()
    }

    // MARK: - Notifications

    private func scheduleNotification(after seconds: Int) {
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "Time for your next set 💪"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
    }

    // MARK: - Haptics

    private func playCompletionHaptic() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.notification)
        #endif
    }
}
