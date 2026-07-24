import Foundation

enum WorkoutDevice: String, Codable, Hashable {
    case phone
    case watch
}

struct SessionVersion: Codable, Hashable, Comparable {
    var ownershipEpoch: UInt32
    var revision: UInt64

    static let initial = SessionVersion(ownershipEpoch: 0, revision: 0)

    static func < (lhs: SessionVersion, rhs: SessionVersion) -> Bool {
        lhs.ownershipEpoch == rhs.ownershipEpoch
            ? lhs.revision < rhs.revision
            : lhs.ownershipEpoch < rhs.ownershipEpoch
    }

    func advanced() -> SessionVersion {
        SessionVersion(ownershipEpoch: ownershipEpoch, revision: revision + 1)
    }

    func transferred() -> SessionVersion {
        SessionVersion(ownershipEpoch: ownershipEpoch + 1, revision: 0)
    }
}

struct RestTimerSnapshot: Codable, Hashable {
    var endDate: Date
    var totalSeconds: Int
    /// A paused timer has no meaningful wall-clock end date. Keep its remaining
    /// duration in the replica so a mirror can pause at exactly the same point.
    var pausedRemainingSeconds: Int?

    init(endDate: Date, totalSeconds: Int, pausedRemainingSeconds: Int? = nil) {
        self.endDate = endDate
        self.totalSeconds = totalSeconds
        self.pausedRemainingSeconds = pausedRemainingSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case endDate, totalSeconds, pausedRemainingSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        endDate = try c.decode(Date.self, forKey: .endDate)
        totalSeconds = try c.decode(Int.self, forKey: .totalSeconds)
        pausedRemainingSeconds = try c.decodeIfPresent(Int.self, forKey: .pausedRemainingSeconds)
    }
}

/// One self-contained, atomically persisted/published view of a workout.
struct WorkoutReplica: Codable, Hashable {
    var session: WorkoutSession
    var owner: WorkoutDevice
    var version: SessionVersion
    var currentExerciseIndex: Int
    var restTimer: RestTimerSnapshot?
    var isWorkoutPaused: Bool
    var healthRecorder: WorkoutDevice?

    init(
        session: WorkoutSession,
        owner: WorkoutDevice,
        version: SessionVersion = .initial,
        currentExerciseIndex: Int = 0,
        restTimer: RestTimerSnapshot? = nil,
        isWorkoutPaused: Bool = false,
        healthRecorder: WorkoutDevice? = nil
    ) {
        self.session = session
        self.owner = owner
        self.version = version
        self.currentExerciseIndex = currentExerciseIndex
        self.restTimer = restTimer
        self.isWorkoutPaused = isWorkoutPaused
        self.healthRecorder = healthRecorder
    }

    private enum CodingKeys: String, CodingKey {
        case session, owner, version, currentExerciseIndex, restTimer
        case isWorkoutPaused, healthRecorder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        session = try c.decode(WorkoutSession.self, forKey: .session)
        owner = try c.decode(WorkoutDevice.self, forKey: .owner)
        version = try c.decode(SessionVersion.self, forKey: .version)
        currentExerciseIndex = try c.decode(Int.self, forKey: .currentExerciseIndex)
        restTimer = try c.decodeIfPresent(RestTimerSnapshot.self, forKey: .restTimer)
        isWorkoutPaused = try c.decodeIfPresent(
            Bool.self, forKey: .isWorkoutPaused
        ) ?? false
        healthRecorder = try c.decodeIfPresent(
            WorkoutDevice.self, forKey: .healthRecorder
        )
    }
}

enum WorkoutAuthorityState: String, Codable, Hashable {
    case authoritative
    case mirror
    case offeringTransfer
    case requestingTakeover
    case finalizing
}

enum WorkoutSyncStatus: String, Codable, Hashable {
    case localOnly
    case waitingForWatch
    case savedOnWatch
    case waitingForPhone
    case synced
    case needsResync
}

/// Extensible wire kind. Unknown strings remain decodable on older apps.
struct WorkoutMessageKind: RawRepresentable, Codable, Hashable {
    var rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let ownershipOffer = WorkoutMessageKind(rawValue: "ownershipOffer")
    static let ownershipAcceptance = WorkoutMessageKind(rawValue: "ownershipAcceptance")
    static let ownershipCommit = WorkoutMessageKind(rawValue: "ownershipCommit")
    static let takeoverRequest = WorkoutMessageKind(rawValue: "takeoverRequest")
    static let checkpoint = WorkoutMessageKind(rawValue: "checkpoint")
    static let planCache = WorkoutMessageKind(rawValue: "planCache")
    static let tombstone = WorkoutMessageKind(rawValue: "tombstone")
    static let acknowledgment = WorkoutMessageKind(rawValue: "acknowledgment")
}

struct WorkoutMessageEnvelope: Identifiable, Codable, Hashable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var id: UUID
    var kind: WorkoutMessageKind
    var sender: WorkoutDevice
    var sessionID: UUID?
    var createdAt: Date
    /// Opaque kind-specific JSON preserves forward compatibility.
    var payload: Data

    init<Payload: Encodable>(
        id: UUID = UUID(),
        kind: WorkoutMessageKind,
        sender: WorkoutDevice,
        sessionID: UUID?,
        createdAt: Date = Date(),
        payload: Payload
    ) throws {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.kind = kind
        self.sender = sender
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.payload = try JSONEncoder().encode(payload)
    }

    func decodePayload<Payload: Decodable>(_ type: Payload.Type) throws -> Payload {
        try JSONDecoder().decode(type, from: payload)
    }
}

struct WorkoutOwnershipOffer: Codable, Hashable {
    var replica: WorkoutReplica
}

struct WorkoutOwnershipAcceptance: Codable, Hashable {
    var replica: WorkoutReplica
    var acceptedMessageID: UUID
}

struct WorkoutOwnershipCommit: Codable, Hashable {
    var replica: WorkoutReplica
    var acceptedMessageID: UUID
}

struct WorkoutTakeoverRequest: Codable, Hashable {
    var requester: WorkoutDevice
    var knownVersion: SessionVersion
}

struct WorkoutCheckpoint: Codable, Hashable {
    var replica: WorkoutReplica
}

struct WorkoutAcknowledgment: Codable, Hashable {
    var messageIDs: [UUID]
}

struct WorkoutTombstone: Codable, Hashable {
    var sessionID: UUID
    var finalVersion: SessionVersion
    var finished: Bool
    var createdAt: Date
}

struct WorkoutFinalization: Codable, Hashable {
    var tombstone: WorkoutTombstone
    var finalSession: WorkoutSession
    var healthSaved: Bool
}

enum WorkoutMessageTransport: String, Codable, Hashable {
    case context
    case reliable
}

struct PendingWorkoutMessage: Identifiable, Codable, Hashable {
    var id: UUID
    var payload: Data
    var createdAt: Date
    var attemptCount: Int
    var transport: WorkoutMessageTransport

    init(
        id: UUID = UUID(),
        payload: Data,
        createdAt: Date = Date(),
        attemptCount: Int = 0,
        transport: WorkoutMessageTransport = .reliable
    ) {
        self.id = id
        self.payload = payload
        self.createdAt = createdAt
        self.attemptCount = attemptCount
        self.transport = transport
    }

    private enum CodingKeys: String, CodingKey {
        case id, payload, createdAt, attemptCount, transport
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        payload = try c.decode(Data.self, forKey: .payload)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        attemptCount = try c.decode(Int.self, forKey: .attemptCount)
        transport = try c.decodeIfPresent(
            WorkoutMessageTransport.self,
            forKey: .transport
        ) ?? .reliable
    }
}

struct WorkoutRuntimeState: Codable, Hashable {
    var schemaVersion: Int
    var activeReplica: WorkoutReplica?
    var authorityState: WorkoutAuthorityState?
    var syncStatus: WorkoutSyncStatus
    var outbox: [PendingWorkoutMessage]
    var processedMessageIDs: [UUID]
    var terminalSessions: [UUID: WorkoutTombstone]
    /// The latest self-contained plans the Watch can start while the phone is
    /// unavailable. Kept beside the active runtime so it is atomically durable.
    var watchPlanCache: WatchPlanCache?

    init(
        schemaVersion: Int = WorkoutMessageEnvelope.currentSchemaVersion,
        activeReplica: WorkoutReplica? = nil,
        authorityState: WorkoutAuthorityState? = nil,
        syncStatus: WorkoutSyncStatus = .localOnly,
        outbox: [PendingWorkoutMessage] = [],
        processedMessageIDs: [UUID] = [],
        terminalSessions: [UUID: WorkoutTombstone] = [:],
        watchPlanCache: WatchPlanCache? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.activeReplica = activeReplica
        self.authorityState = authorityState
        self.syncStatus = syncStatus
        self.outbox = outbox
        self.processedMessageIDs = processedMessageIDs
        self.terminalSessions = terminalSessions
        self.watchPlanCache = watchPlanCache
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, activeReplica, authorityState, syncStatus, outbox
        case processedMessageIDs, terminalSessions, watchPlanCache
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? WorkoutMessageEnvelope.currentSchemaVersion
        activeReplica = try c.decodeIfPresent(WorkoutReplica.self, forKey: .activeReplica)
        authorityState = try c.decodeIfPresent(WorkoutAuthorityState.self, forKey: .authorityState)
        syncStatus = try c.decodeIfPresent(WorkoutSyncStatus.self, forKey: .syncStatus) ?? .localOnly
        outbox = try c.decodeIfPresent([PendingWorkoutMessage].self, forKey: .outbox) ?? []
        processedMessageIDs = try c.decodeIfPresent([UUID].self, forKey: .processedMessageIDs) ?? []
        terminalSessions = try c.decodeIfPresent([UUID: WorkoutTombstone].self, forKey: .terminalSessions) ?? [:]
        watchPlanCache = try c.decodeIfPresent(WatchPlanCache.self, forKey: .watchPlanCache)
    }

    func accepts(_ replica: WorkoutReplica) -> Bool {
        guard terminalSessions[replica.session.id] == nil else { return false }
        guard let current = activeReplica else { return true }
        if current.session.id != replica.session.id {
            return replica.session.startedAt > current.session.startedAt
        }
        return replica.version > current.version
    }
}
