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

        startTicker()
        onStateChange?()
    }

    func pause() {
        guard isRunning, let endDate else { return }
        let remaining = max(0, Int(endDate.timeIntervalSinceNow.rounded()))
        secondsRemaining = remaining
        self.endDate = nil
        isRunning = false
        isPaused = true
        stopTicker()
        onStateChange?()
    }

    func resume() {
        guard isPaused || (!isRunning && secondsRemaining > 0) else { return }
        endDate = Date().addingTimeInterval(TimeInterval(secondsRemaining))
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
    }

    func sync(endDate: Date, totalSeconds: Int) {
        let remaining = Int(endDate.timeIntervalSinceNow.rounded())
        guard remaining > 0 else {
            stop()
            return
        }
        self.totalSeconds = totalSeconds
        self.endDate = endDate
        self.secondsRemaining = remaining
        self.isRunning = true
        self.isPaused = false
        self.hasCompleted = false
        startTicker()
    }

    func syncPaused(remainingSeconds: Int, totalSeconds: Int) {
        stopTicker()
        self.totalSeconds = totalSeconds
        self.secondsRemaining = remainingSeconds
        self.endDate = nil
        self.isRunning = false
        self.isPaused = true
        self.hasCompleted = false
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
        if remaining <= 0 {
            secondsRemaining = 0
            stopTicker()
            isRunning = false
            isPaused = false
            hasCompleted = true
            triggerCompletionAlerts()
            onCompletion?()
            onStateChange?()
        } else {
            secondsRemaining = remaining
        }
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
