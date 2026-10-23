#if canImport(Network)
    import Foundation
    import Network
    import os

    /// Where a link stands, in words a person can read.
    public enum HmmLinkState: Equatable, Sendable {
        case off
        /// Listening (the host) or looking (the companion).
        case waiting
        /// Joined to the named device.
        case connected(String)
        case failed(String)

        public var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    /// One connection that carries frames both ways.
    @MainActor
    final class HmmLinkPipe {
        let connection: NWConnection
        private var reader = HmmFrameReader()
        var onFrame: ((Data) -> Void)?
        var onClose: (() -> Void)?

        init(_ connection: NWConnection) {
            self.connection = connection
        }

        var name: String {
            if case let .service(name, _, _, _) = connection.endpoint { return name }
            return "\(connection.endpoint)"
        }

        func start() {
            connection.start(queue: .main)
            receive()
        }

        func send(_ payload: Data) {
            connection.send(content: HmmFrames.frame(payload), completion: .contentProcessed { _ in })
        }

        func cancel() {
            connection.cancel()
        }

        private func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, complete, error in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let data {
                        do {
                            for frame in try self.reader.read(data) {
                                self.onFrame?(frame)
                            }
                        } catch {
                            self.connection.cancel()
                            self.onClose?()
                            return
                        }
                    }
                    if complete || error != nil {
                        self.connection.cancel()
                        self.onClose?()
                    } else {
                        self.receive()
                    }
                }
            }
        }
    }

    private func linkParameters() -> NWParameters {
        let parameters = NWParameters.tcp
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
        }
        parameters.includePeerToPeer = true
        return parameters
    }

    /// The host's side (the iPad): advertises itself on the local network under a Bonjour type and talks to whoever
    /// joins. Nothing leaves the local network.
    @MainActor
    public final class HmmLinkHost {
        private let type: String
        private let name: String
        private var listener: NWListener?
        private var pipes: [HmmLinkPipe] = []
        private let logger = Logger(subsystem: "studio.h.kit", category: "link")
        public private(set) var state: HmmLinkState = .off {
            didSet { onState?(state) }
        }

        public var onState: ((HmmLinkState) -> Void)?
        public var onFrame: ((Data) -> Void)?

        /// `type` is the Bonjour type (`_maquette._tcp`), `name` what the companion shows (the device's name).
        public init(type: String, name: String) {
            self.type = type
            self.name = name
        }

        public var isRunning: Bool { listener != nil }

        public func start() {
            guard listener == nil else { return }
            do {
                let listener = try NWListener(using: linkParameters())
                listener.service = NWListener.Service(name: name, type: type)
                listener.newConnectionHandler = { [weak self] connection in
                    MainActor.assumeIsolated { self?.accept(connection) }
                }
                listener.stateUpdateHandler = { [weak self] update in
                    MainActor.assumeIsolated { self?.listenerChanged(update) }
                }
                listener.start(queue: .main)
                self.listener = listener
                state = .waiting
            } catch {
                logger.error("Link host: \(error.localizedDescription)")
                state = .failed(error.localizedDescription)
            }
        }

        public func stop() {
            listener?.cancel()
            listener = nil
            for pipe in pipes {
                pipe.cancel()
            }
            pipes = []
            state = .off
        }

        /// To every companion joined.
        public func send(_ payload: Data) {
            for pipe in pipes {
                pipe.send(payload)
            }
        }

        private func listenerChanged(_ update: NWListener.State) {
            switch update {
            case let .failed(error):
                state = .failed(error.localizedDescription)
            case .ready where pipes.isEmpty:
                state = .waiting
            default:
                break
            }
        }

        private func accept(_ connection: NWConnection) {
            let pipe = HmmLinkPipe(connection)
            pipe.onFrame = { [weak self] in self?.onFrame?($0) }
            pipe.onClose = { [weak self, weak pipe] in
                guard let self else { return }
                pipes.removeAll { $0 === pipe }
                if pipes.isEmpty, listener != nil { state = .waiting }
            }
            pipes.append(pipe)
            pipe.start()
            state = .connected(pipe.name)
        }
    }

    /// The companion's side (the iPhone): looks for a host of the Bonjour type and keeps joined to the first one it
    /// finds, looking again whenever the link drops.
    @MainActor
    public final class HmmLinkCompanion {
        private let type: String
        private var browser: NWBrowser?
        private var pipe: HmmLinkPipe?
        public private(set) var state: HmmLinkState = .off {
            didSet { onState?(state) }
        }

        public var onState: ((HmmLinkState) -> Void)?
        public var onFrame: ((Data) -> Void)?

        public init(type: String) {
            self.type = type
        }

        public func start() {
            guard browser == nil else { return }
            let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: linkParameters())
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                MainActor.assumeIsolated {
                    guard let self, self.pipe == nil, let result = results.first else { return }
                    self.join(result.endpoint)
                }
            }
            browser.start(queue: .main)
            self.browser = browser
            state = .waiting
        }

        public func stop() {
            browser?.cancel()
            browser = nil
            pipe?.cancel()
            pipe = nil
            state = .off
        }

        public func send(_ payload: Data) {
            pipe?.send(payload)
        }

        private func join(_ endpoint: NWEndpoint) {
            let connection = NWConnection(to: endpoint, using: linkParameters())
            let pipe = HmmLinkPipe(connection)
            let name: String = if case let .service(service, _, _, _) = endpoint {
                service
            } else { "\(endpoint)" }
            pipe.onFrame = { [weak self] in self?.onFrame?($0) }
            pipe.onClose = { [weak self] in self?.dropped() }
            connection.stateUpdateHandler = { [weak self] update in
                MainActor.assumeIsolated {
                    if case .ready = update { self?.state = .connected(name) }
                }
            }
            self.pipe = pipe
            pipe.start()
        }

        private func dropped() {
            pipe = nil
            guard browser != nil else { return }
            state = .waiting
            // Look again: restarting the browser reports the host afresh.
            browser?.cancel()
            browser = nil
            start()
        }
    }
#endif
