import Foundation
import Combine
import UserNotifications

#if os(iOS)
import UIKit
#endif
import AVFoundation
#if os(watchOS)
import WatchKit
#endif

/// A countdown rest timer that survives backgrounding via a scheduled local
/// notification and fires a haptic when it completes. Used after each set.
@MainActor
final class RestTimerManager: NSObject, ObservableObject, @preconcurrency AVSpeechSynthesizerDelegate {
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var totalSeconds: Int = 0
    @Published private(set) var secondsRemaining: Int = 0
    /// Seconds elapsed past the target. The timer alerts on reaching zero and
    /// then keeps counting rather than stopping — resting longer is the user's
    /// decision, and the extra time should be visible, not hidden.
    @Published private(set) var overtimeSeconds: Int = 0

    var isOvertime: Bool { overtimeSeconds > 0 }

    private(set) var endDate: Date?
    private var ticker: Timer?
    private let notificationID = "aru.rest.timer"
    private var alertsEnabled = true
    private(set) var alertConfiguration: RestTimerAlertConfiguration = .default
    private var lastSpokenSecond: Int?
    /// Latches at the zero crossing so the completion alert fires exactly once
    /// per run instead of on every tick through overtime.
    private var hasReachedZero = false
    var onStateChange: (() -> Void)?
    let localDevice: WorkoutDevice

    /// Retained for the lifetime of the timer so spoken countdown cues are not
    /// deallocated mid-utterance.
    ///
    /// Only the iPhone speaks. The Watch runs the same mirrored timer and keeps
    /// its haptics, but allowing both copies to synthesize speech produces
    /// duplicate, unsynchronized announcements from two physical devices.
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var activeUtterance: AVSpeechUtterance?
    var spokenAlertsEnabled: Bool {
        Self.spokenAlertsEnabled(for: localDevice)
    }

    nonisolated static func spokenAlertsEnabled(for device: WorkoutDevice) -> Bool {
        device == .phone
    }

    init(localDevice: WorkoutDevice) {
        self.localDevice = localDevice
        super.init()
        speechSynthesizer.delegate = self
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalSeconds - secondsRemaining) / Double(totalSeconds)
    }

    var formattedRemaining: String {
        if isOvertime {
            return String(format: "+%d:%02d", overtimeSeconds / 60, overtimeSeconds % 60)
        }
        let s = max(0, secondsRemaining)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    nonisolated static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func start(seconds: Int, configuration: RestTimerAlertConfiguration = .default) {
        guard seconds > 0 else { return }
        alertConfiguration = configuration
        alertsEnabled = configuration.alertsEnabled
        lastSpokenSecond = nil
        hasReachedZero = false
        overtimeSeconds = 0
        totalSeconds = seconds
        secondsRemaining = seconds
        isPaused = false
        endDate = Date().addingTimeInterval(TimeInterval(seconds))
        isRunning = true
        startTicker()
        if alertsEnabled, configuration.style == .soundAndHaptic { scheduleNotification(after: seconds) }
        onStateChange?()
    }

    func add(seconds: Int) {
        // Extending from overtime returns the timer to a normal countdown and
        // re-arms the completion alert for the new target.
        if isOvertime {
            overtimeSeconds = 0
            hasReachedZero = false
            lastSpokenSecond = nil
        }
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
        if alertsEnabled, alertConfiguration.style == .soundAndHaptic {
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
        // Overtime is a legitimate paused state: the rest is over but the user
        // has not moved on yet, so freeze the elapsed overtime rather than
        // treating it as "nothing left to resume".
        isPaused = secondsRemaining > 0 || isOvertime
        endDate = nil
        ticker?.invalidate()
        ticker = nil
        cancelNotification()
        stopSpokenAlert()
        onStateChange?()
    }

    func resume() {
        guard isPaused, secondsRemaining > 0 || isOvertime else { return }
        isPaused = false
        isRunning = true
        // Rewind the end date so ticking resumes exactly where overtime paused.
        endDate = isOvertime
            ? Date().addingTimeInterval(-TimeInterval(overtimeSeconds))
            : Date().addingTimeInterval(TimeInterval(secondsRemaining))
        startTicker()
        if alertsEnabled, alertConfiguration.style == .soundAndHaptic { scheduleNotification(after: secondsRemaining) }
        onStateChange?()
    }

    func stop() {
        isRunning = false
        isPaused = false
        endDate = nil
        secondsRemaining = 0
        overtimeSeconds = 0
        hasReachedZero = false
        ticker?.invalidate()
        ticker = nil
        cancelNotification()
        stopSpokenAlert()
        onStateChange?()
    }

    func reset() {
        guard totalSeconds > 0 else { return }
        stopSpokenAlert()
        lastSpokenSecond = nil
        hasReachedZero = false
        overtimeSeconds = 0
        secondsRemaining = totalSeconds
        isPaused = false
        isRunning = true
        endDate = Date().addingTimeInterval(TimeInterval(totalSeconds))
        startTicker()
        cancelNotification()
        if alertsEnabled, alertConfiguration.style == .soundAndHaptic { scheduleNotification(after: totalSeconds) }
        onStateChange?()
    }

    func sync(endDate: Date, totalSeconds: Int, configuration: RestTimerAlertConfiguration = .default) {
        alertConfiguration = configuration
        alertsEnabled = configuration.alertsEnabled
        lastSpokenSecond = nil
        self.totalSeconds = totalSeconds
        self.endDate = endDate
        let remaining = Int(ceil(endDate.timeIntervalSinceNow))
        self.secondsRemaining = max(0, remaining)
        // A past end date means the owner is already in overtime. Adopt that
        // state instead of coercing it to "finished", and latch the alert so
        // this device doesn't replay a completion the owner already announced.
        self.overtimeSeconds = remaining < 0 ? -remaining : 0
        self.hasReachedZero = remaining <= 0
        self.isRunning = true
        self.isPaused = false
        startTicker()
    }

    /// Applies a remote paused timer without inventing a local end date or
    /// firing an alert. This intentionally does not invoke `onStateChange`:
    /// the replica is already the source of truth.
    func syncPaused(remainingSeconds: Int, totalSeconds: Int, configuration: RestTimerAlertConfiguration = .default) {
        alertConfiguration = configuration
        alertsEnabled = configuration.alertsEnabled
        self.totalSeconds = max(totalSeconds, remainingSeconds)
        self.secondsRemaining = max(0, remainingSeconds)
        // Negative remaining encodes paused-in-overtime on the wire.
        self.overtimeSeconds = remainingSeconds < 0 ? -remainingSeconds : 0
        self.hasReachedZero = remainingSeconds <= 0
        self.endDate = nil
        self.isRunning = false
        self.isPaused = remainingSeconds != 0
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
        guard remaining <= 0 else {
            overtimeSeconds = 0
            return
        }
        // Reaching zero alerts once and then keeps counting. The timer never
        // ends the rest itself and never moves to the next exercise — only the
        // user does that, by logging the next set or navigating.
        if !hasReachedZero {
            hasReachedZero = true
            cancelNotification()
            playCompletionAlert()
            onStateChange?()
        }
        overtimeSeconds = -remaining
    }

    private func finish(playHaptic: Bool) {
        isRunning = false
        isPaused = false
        endDate = nil
        secondsRemaining = 0
        overtimeSeconds = 0
        hasReachedZero = false
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
        guard alertConfiguration.earlyCueEnabled,
              ([alertConfiguration.earlyCueLeadSeconds, 3, 2, 1].contains(seconds)),
              lastSpokenSecond != seconds else { return }
        lastSpokenSecond = seconds

        // A single early haptic gets the user's attention without repeatedly
        // interrupting HealthKit heart-rate sampling during the 3-2-1 speech.
        if seconds == alertConfiguration.earlyCueLeadSeconds {
            #if os(watchOS)
            WKInterfaceDevice.current().play(.start)
            #endif
            speak("Get ready for your next set")
        } else {
            speak(String(seconds))
        }
    }

    private func playCompletionAlert() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.notification)
        #endif
        if alertConfiguration.style == .soundAndHaptic {
        speak("Go. Start your next set.")
        }
    }

    private func stopSpokenAlert() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        activeUtterance = nil
        deactivateSpeechAudioSession()
    }

    private func speak(_ text: String) {
        guard spokenAlertsEnabled else { return }

        // Drop any delayed phrase before announcing the current cue. This keeps
        // "three, two, one" aligned even if the selected voice starts slowly.
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        activateSpeechAudioSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en-US")
        utterance.rate = 0.55
        utterance.volume = 1
        activeUtterance = utterance
        speechSynthesizer.speak(utterance)
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        finishSpeaking(utterance)
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        finishSpeaking(utterance)
    }

    private func finishSpeaking(_ utterance: AVSpeechUtterance) {
        guard activeUtterance === utterance else { return }
        activeUtterance = nil
        deactivateSpeechAudioSession()
    }

    private func activateSpeechAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [
                    .duckOthers,
                    .interruptSpokenAudioAndMixWithOthers,
                    .allowBluetoothA2DP
                ]
            )
            try session.setActive(true)
        } catch {
            // Speech can still use the current application audio session. A
            // route/session failure should never stop the workout timer.
        }
        #endif
    }

    private func deactivateSpeechAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        } catch {
            // Another audio client may already have changed the shared session.
        }
        #endif
    }
}
