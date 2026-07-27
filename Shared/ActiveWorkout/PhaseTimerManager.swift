import Foundation
import Combine
import OSLog

#if canImport(AVFoundation)
import AVFoundation
#endif

#if os(iOS)
import UIKit
import AudioToolbox
#elseif os(watchOS)
import WatchKit
#endif

/// Drives countdown timers, alerts, and voice announcements for multi-phase routine phases.
@MainActor
final class PhaseTimerManager: ObservableObject {
    @Published private(set) var secondsRemaining: Int = 0
    @Published private(set) var totalSeconds: Int = 0
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var endDate: Date?
    @Published private(set) var hasCompleted: Bool = false
    /// Seconds elapsed past the phase's target duration. The phase alerts on
    /// reaching zero and then keeps counting — deciding to spend five more
    /// minutes on the machine is the user's call, and that time is real.
    @Published private(set) var overtimeSeconds: Int = 0

    var isOvertime: Bool { overtimeSeconds > 0 }

    /// Formatted for display: `12:34` while counting down, `+2:05` in overtime.
    var formattedRemaining: String {
        if isOvertime {
            return String(format: "+%d:%02d", overtimeSeconds / 60, overtimeSeconds % 60)
        }
        let s = max(0, secondsRemaining)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    var onStateChange: (() -> Void)?
    var onCompletion: (() -> Void)?

    private var timerSubscription: AnyCancellable?
    #if canImport(AVFoundation)
    private var speechSynthesizer: AVSpeechSynthesizer?
    #endif

    init() {
        #if canImport(AVFoundation)
        speechSynthesizer = AVSpeechSynthesizer()
        #endif
    }

    func start(seconds: Int) {
        guard seconds > 0 else { return }
        totalSeconds = seconds
        secondsRemaining = seconds
        endDate = Date().addingTimeInterval(TimeInterval(seconds))
        isRunning = true
        isPaused = false
        hasCompleted = false
        overtimeSeconds = 0

        startTicker()
        onStateChange?()
    }

    func pause() {
        guard isRunning, let endDate else { return }
        let raw = Int(endDate.timeIntervalSinceNow.rounded())
        secondsRemaining = max(0, raw)
        // Freeze accumulated overtime rather than discarding it.
        overtimeSeconds = raw < 0 ? -raw : 0
        self.endDate = nil
        isRunning = false
        isPaused = true
        stopTicker()
        onStateChange?()
    }

    func resume() {
        guard isPaused || (!isRunning && (secondsRemaining > 0 || isOvertime)) else { return }
        endDate = isOvertime
            ? Date().addingTimeInterval(-TimeInterval(overtimeSeconds))
            : Date().addingTimeInterval(TimeInterval(secondsRemaining))
        isRunning = true
        isPaused = false
        startTicker()
        onStateChange?()
    }

    func add(seconds: Int) {
        if isRunning, let currentEnd = endDate {
            let newEnd = currentEnd.addingTimeInterval(TimeInterval(seconds))
            let newRemaining = max(1, Int(newEnd.timeIntervalSinceNow.rounded()))
            totalSeconds = max(totalSeconds, newRemaining)
            endDate = newEnd
            secondsRemaining = newRemaining
        } else {
            let newRemaining = max(1, secondsRemaining + seconds)
            secondsRemaining = newRemaining
            totalSeconds = max(totalSeconds, newRemaining)
        }
        // Extending from overtime pulls the phase back into a normal countdown,
        // and re-arms the completion alert for the new target.
        overtimeSeconds = 0
        hasCompleted = false
        onStateChange?()
    }

    func stop() {
        stopTicker()
        endDate = nil
        secondsRemaining = 0
        totalSeconds = 0
        isRunning = false
        isPaused = false
        hasCompleted = false
        overtimeSeconds = 0
    }

    func sync(endDate: Date, totalSeconds: Int) {
        let remaining = Int(endDate.timeIntervalSinceNow.rounded())
        self.totalSeconds = totalSeconds
        self.endDate = endDate
        self.secondsRemaining = max(0, remaining)
        // A past end date is the owner running in overtime, not a finished
        // phase. Adopting it as overtime keeps both devices showing the same
        // elapsed time; stopping here would blank the peer's timer instead.
        self.overtimeSeconds = remaining < 0 ? -remaining : 0
        self.isRunning = true
        self.isPaused = false
        self.hasCompleted = remaining <= 0
        startTicker()
    }

    func syncPaused(remainingSeconds: Int, totalSeconds: Int) {
        stopTicker()
        self.totalSeconds = totalSeconds
        self.secondsRemaining = max(0, remainingSeconds)
        // Negative remaining encodes paused-in-overtime on the wire.
        self.overtimeSeconds = remainingSeconds < 0 ? -remainingSeconds : 0
        self.endDate = nil
        self.isRunning = false
        self.isPaused = true
        self.hasCompleted = remainingSeconds <= 0
    }

    private func startTicker() {
        stopTicker()
        timerSubscription = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func stopTicker() {
        timerSubscription?.cancel()
        timerSubscription = nil
    }

    private func tick() {
        guard isRunning, let endDate else { return }
        let remaining = Int(endDate.timeIntervalSinceNow.rounded())
        guard remaining <= 0 else {
            secondsRemaining = remaining
            overtimeSeconds = 0
            return
        }
        secondsRemaining = 0
        // Reaching zero alerts once and then keeps running into overtime. The
        // phase never ends itself and never advances — only the user does, via
        // the transition sheet or the phase controls.
        if !hasCompleted {
            hasCompleted = true
            triggerCompletionAlerts()
            onCompletion?()
            onStateChange?()
        }
        overtimeSeconds = -remaining
    }

    func triggerCompletionAlerts(message: String? = nil) {
        playHapticAlert()
        playAudioChime()
        if let message {
            speakAnnouncement(message)
        }
    }

    func playHapticAlert() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.notification)
        #endif
    }

    func playAudioChime() {
        #if os(iOS)
        AudioServicesPlaySystemSound(1005)
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.directionUp)
        #endif
    }

    func speakAnnouncement(_ text: String) {
        #if canImport(AVFoundation)
        guard let synth = speechSynthesizer else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        synth.speak(utterance)
        #endif
    }
}
