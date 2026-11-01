#if canImport(GroupActivities) && canImport(CoreTransferable)
    import CoreTransferable
    import Foundation
    import GroupActivities
    import UniformTypeIdentifiers

    /// A file handed to everyone in a SharePlay session (the project being reviewed), through the session's journal.
    public struct HmmTogetherFile: Transferable, Sendable {
        public let url: URL

        public init(url: URL) {
            self.url = url
        }

        public static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(contentType: .data) { file in
                SentTransferredFile(file.url)
            } importing: { received in
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Together \(UUID().uuidString)")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let copy = folder.appendingPathComponent(received.file.lastPathComponent)
                try FileManager.default.copyItem(at: received.file, to: copy)
                return HmmTogetherFile(url: copy)
            }
        }
    }

    /// What travels between the people in a session: the app's own message, already encoded.
    struct HmmTogetherPacket: Codable, Sendable {
        var payload: Data
    }

    /// A SharePlay session over FaceTime for any activity: messages (reliable for what must arrive, quick for what is
    /// replaced a moment later, like a view), files, and who is in it. The app decides what its messages mean.
    @MainActor
    public final class HmmTogether<Activity: GroupActivity> {
        public private(set) var session: GroupSession<Activity>?
        private var reliable: GroupSessionMessenger?
        private var quick: GroupSessionMessenger?
        private var journal: GroupSessionJournal?
        private var tasks: [Task<Void, Never>] = []

        public var onMessage: ((Data) -> Void)?
        public var onFile: ((URL) -> Void)?
        /// How many people are in it, this device included.
        public var onPeople: ((Int) -> Void)?
        public var onEnd: (() -> Void)?

        public init() {}

        public var isActive: Bool { session != nil }

        /// Offers `activity` to the people on the FaceTime call (the system asks the person first). True when it
        /// started.
        public nonisolated static func start(_ activity: Activity) async throws -> Bool {
            switch await activity.prepareForActivation() {
            case .activationPreferred: try await activity.activate()
            default: false
            }
        }

        /// Takes part in `session` (one the system handed the app: started here or by someone else).
        public func join(_ session: GroupSession<Activity>) {
            leave()
            self.session = session
            let reliable = GroupSessionMessenger(session: session, deliveryMode: .reliable)
            let quick = GroupSessionMessenger(session: session, deliveryMode: .unreliable)
            let journal = GroupSessionJournal(session: session)
            self.reliable = reliable
            self.quick = quick
            self.journal = journal
            tasks.append(Task { [weak self] in
                for await (packet, _) in reliable.messages(of: HmmTogetherPacket.self) {
                    self?.onMessage?(packet.payload)
                }
            })
            tasks.append(Task { [weak self] in
                for await (packet, _) in quick.messages(of: HmmTogetherPacket.self) {
                    self?.onMessage?(packet.payload)
                }
            })
            tasks.append(Task { [weak self] in
                for await attachments in journal.attachments {
                    for attachment in attachments {
                        if let file = try? await attachment.load(HmmTogetherFile.self) { self?.onFile?(file.url) }
                    }
                }
            })
            tasks.append(Task { [weak self] in
                for await people in session.$activeParticipants.values {
                    self?.onPeople?(people.count)
                }
            })
            tasks.append(Task { [weak self] in
                for await state in session.$state.values {
                    if case .invalidated = state { self?.ended() }
                }
            })
            session.join()
        }

        public func send(_ payload: Data, reliable isReliable: Bool = true) {
            guard let messenger = isReliable ? reliable : quick else { return }
            let packet = HmmTogetherPacket(payload: payload)
            Task { try? await messenger.send(packet) }
        }

        /// Hands a file to everyone in the session, and to anyone who joins later.
        public func share(_ file: URL) {
            guard let journal else { return }
            Task { _ = try? await journal.add(HmmTogetherFile(url: file)) }
        }

        /// Leaves; the others carry on.
        public func leave() {
            session?.leave()
            ended()
        }

        /// Ends it for everyone.
        public func endForEveryone() {
            session?.end()
            ended()
        }

        private func ended() {
            guard session != nil else { return }
            for task in tasks {
                task.cancel()
            }
            tasks = []
            session = nil
            reliable = nil
            quick = nil
            journal = nil
            onEnd?()
        }
    }

    /// Whether this device is on a FaceTime call that can share an activity (what shows "Review over FaceTime").
    @MainActor @Observable
    public final class HmmTogetherCall {
        public private(set) var isOn = false
        @ObservationIgnored private let observer = GroupStateObserver()
        @ObservationIgnored private var task: Task<Void, Never>?

        public init() {
            isOn = observer.isEligibleForGroupSession
            let observer = observer
            task = Task { [weak self] in
                for await value in observer.$isEligibleForGroupSession.values {
                    self?.isOn = value
                }
            }
        }
    }
#endif
