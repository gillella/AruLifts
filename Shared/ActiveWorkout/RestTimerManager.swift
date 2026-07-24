import Foundation
import Combine
import UserNotifications

#if os(iOS)
import UIKit
#elseif os(watchOS)
import AVFoundation
import WatchKit
#endif

/// A countdown rest timer that survives backgrounding via a scheduled local
/// notification and fires a haptic when it completes. Used after each set.
@MainActor
final class RestTimerManager: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var totalSeconds: Int = 0
    @Published private(set) var secondsRemaining: Int = 0

    private(set) var endDate: Date?
    private var ticker: Timer?
    private let notificationID = "aru.rest.timer"
    private var alertsEnabled = true
    private var lastSpokenSecond: Int?
    var onStateChange: (() -> Void)?

    #if os(watchOS)
    /// Retained for the lifetime of the timer so spoken countdown cues are not
    /// deallocated mid-utterance. AVSpeechSynthesizer routes to connected
    /// Bluetooth earphones when present and otherwise uses the Watch audio route.
    private let speechSynthesizer = AVSpeechSynthesizer()
    #endif

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
        self.alertsEnabled = alertsEnabled
        lastSpokenSecond = nil
        totalSeconds = seconds
        secondsRemaining = seconds
        isPaused = false
        endDate = Date().addingTimeInterval(TimeInterval(seconds))
        isRunning = true
        startTicker()
        if alertsEnabled { scheduleNotification(after: seconds) }
        onStateChange?()
    }

    func add(seconds: Int) {
        if isPaused {
            secondsRemaining = max(1, secondsRemaining + seconds)
            totalSeconds = max(totalSeconds + seconds, 1)
            onStateChange?()
            return
        }
        guard isRunning, let end = endDate else { return }
        let newEnd = end.addingTimeInterval(TimeInterval(seconds))
        endDate = newEnd
        totalSeconds = max(totalSeconds + seconds, 1)
        cancelNotification()
        if alertsEnabled {
            scheduleNotification(after: Int(newEnd.timeIntervalSinceNow))
        }
        tick()
        onStateChange?()
    }

    func skip() {
        finish(playHaptic: false)
    }

    func pause() {
        guard isRunning else { return }
        tick()
        isRunning = false
        isPaused = secondsRemaining > 0
        endDate = nil
        ticker?.invalidate()
        ticker = nil
        cancelNotification()
        stopSpokenAlert()
        onStateChange?()
    }

    func resume() {
        guard isPaused, secondsRemaining > 0 else { return }
        isPaused = false
        isRunning = true
        endDate = Date().addingTimeInterval(TimeInterval(secondsRemaining))
        startTicker()
        if alertsEnabled { scheduleNotification(after: secondsRemaining) }
        onStateChange?()
    }

    func stop() {
        isRunning = false
        isPaused = false
        endDate = nil
        secondsRemaining = 0
        ticker?.invalidate()
        ticker = nil
        cancelNotification()
        stopSpokenAlert()
        onStateChange?()
    }

    func sync(endDate: Date, totalSeconds: Int) {
        alertsEnabled = true
        lastSpokenSecond = nil
        self.totalSeconds = totalSeconds
        self.endDate = endDate
        self.secondsRemaining = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
        self.isRunning = true
        self.isPaused = false
        startTicker()
    }

    /// Applies a remote paused timer without inventing a local end date or
    /// firing an alert. This intentionally does not invoke `onStateChange`:
    /// the replica is already the source of truth.
    func syncPaused(remainingSeconds: Int, totalSeconds: Int) {
        self.totalSeconds = max(totalSeconds, remainingSeconds)
        self.secondsRemaining = max(0, remainingSeconds)
        self.endDate = nil
        self.isRunning = false
        self.isPaused = remainingSeconds > 0
        ticker?.invalidate()
        ticker = nil
        cancelNotification()
        stopSpokenAlert()
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
        if alertsEnabled {
            playCountdownCueIfNeeded(secondsRemaining)
        }
        if remaining <= 0 {
            finish(playHaptic: true)
        }
    }

    private func finish(playHaptic: Bool) {
        isRunning = false
        isPaused = false
        endDate = nil
        secondsRemaining = 0
        ticker?.invalidate()
        ticker = nil
        cancelNotification()
        if playHaptic {
            playCompletionAlert()
        } else {
            stopSpokenAlert()
        }
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

    private func playCountdownCueIfNeeded(_ seconds: Int) {
        #if os(watchOS)
        guard [10, 3, 2, 1].contains(seconds),
              lastSpokenSecond != seconds else { return }
        lastSpokenSecond = seconds

        // A single early haptic gets the user's attention without repeatedly
        // interrupting HealthKit heart-rate sampling during the 3-2-1 speech.
        if seconds == 10 {
            WKInterfaceDevice.current().play(.start)
            speak("Ten seconds")
        } else {
            speak(String(seconds))
        }
        #endif
    }

    private func playCompletionAlert() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.notification)
        speak("Go. Start your next set.")
        #endif
    }

    private func stopSpokenAlert() {
        #if os(watchOS)
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        #endif
    }

    #if os(watchOS)
    private func speak(_ text: String) {
        // Drop any delayed phrase before announcing the current cue. This keeps
        // "three, two, one" aligned even if the selected voice starts slowly.
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en-US")
        utterance.rate = 0.55
        utterance.volume = 1
        speechSynthesizer.speak(utterance)
    }
    #endif
}
