import Foundation
import Combine

/// A timer dedicated to the active timed set.
///
/// It deliberately owns a separate countdown engine from phase and rest
/// timing so a hold can run inside a timed phase and transition into recovery
/// without either timer overwriting the other.
@MainActor
final class ExerciseTimerManager: ObservableObject {
    private let backing: PhaseTimerManager
    private var cancellable: AnyCancellable?
    /// The prescribed set duration. Temporary +/- adjustments change the
    /// countdown but Reset always returns to this value.
    private var targetSeconds = 0

    var secondsRemaining: Int { backing.secondsRemaining }
    var totalSeconds: Int { targetSeconds }
    var isRunning: Bool { backing.isRunning }
    var isPaused: Bool { backing.isPaused }
    var endDate: Date? { backing.endDate }
    var hasCompleted: Bool { backing.hasCompleted }
    var overtimeSeconds: Int { backing.overtimeSeconds }
    var isOvertime: Bool { backing.isOvertime }
    var formattedRemaining: String { backing.formattedRemaining }
    var cueLeadSeconds: Int { backing.cueLeadSeconds }

    var onStateChange: (() -> Void)? {
        didSet { backing.onStateChange = onStateChange }
    }
    var onCompletion: (() -> Void)? {
        didSet { backing.onCompletion = onCompletion }
    }
    var onLeadCue: (() -> String?)? {
        didSet { backing.onLeadCue = onLeadCue }
    }

    init(localDevice: WorkoutDevice = .phone) {
        backing = PhaseTimerManager(localDevice: localDevice)
        cancellable = backing.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    func start(seconds: Int, cueLeadSeconds: Int = 0) {
        targetSeconds = max(0, seconds)
        backing.start(seconds: seconds, cueLeadSeconds: cueLeadSeconds)
    }

    func pause() { backing.pause() }
    func resume() { backing.resume() }
    func add(seconds: Int) { backing.add(seconds: seconds) }
    func stop() {
        targetSeconds = 0
        backing.stop()
    }

    func reset() {
        guard targetSeconds > 0 else { return }
        backing.start(seconds: targetSeconds, cueLeadSeconds: cueLeadSeconds)
    }

    func sync(
        endDate: Date,
        totalSeconds: Int,
        cueLeadSeconds: Int = 0,
        resetLeadCue: Bool = false
    ) {
        targetSeconds = max(0, totalSeconds)
        backing.sync(
            endDate: endDate,
            totalSeconds: totalSeconds,
            cueLeadSeconds: cueLeadSeconds,
            resetLeadCue: resetLeadCue
        )
    }

    func syncPaused(
        remainingSeconds: Int,
        totalSeconds: Int,
        cueLeadSeconds: Int = 0,
        resetLeadCue: Bool = false
    ) {
        targetSeconds = max(0, totalSeconds)
        backing.syncPaused(
            remainingSeconds: remainingSeconds,
            totalSeconds: totalSeconds,
            cueLeadSeconds: cueLeadSeconds,
            resetLeadCue: resetLeadCue
        )
    }

    func speakAnnouncement(_ text: String) {
        backing.speakAnnouncement(text)
    }
}
