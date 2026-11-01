#if canImport(UIKit) && canImport(WebKit)
    import CoreGraphics
    import Foundation

    /// The frames of the web pieces in a scene, one player per piece. An export asks for exact frames and waits; the stage
    /// takes the frame if it's drawn, else the last one it has, and is told when the next one arrives. Both run the same
    /// player steps, so a frame on the stage is the frame in the file.
    @MainActor
    public final class HmmWebFrames {
        /// Pixels per CSS pixel in every picture (the same for the stage and the export, so they match).
        public let scale: CGFloat
        /// How many pieces stay loaded at once; the least recently used is dropped first.
        public let livePlayers: Int
        /// Called when a frame the stage asked for arrives.
        public var onFrame: (() -> Void)?

        private var players: [String: HmmWebPlayer] = [:]
        private var used: [String] = []
        private var ready: [String: [Int: CGImage]] = [:]
        private var latest: [String: CGImage] = [:]
        private var chain: [String: Task<CGImage?, Never>] = [:]
        private var inFlight = Set<String>()

        public init(scale: CGFloat = 1, livePlayers: Int = 4) {
            self.scale = scale
            self.livePlayers = max(livePlayers, 1)
        }

        /// The exact picture of `piece` (named `id`) at `frame`, drawing it if needed.
        public func frame(_ id: String, piece: HmmWebPiece, frame: Int) async -> CGImage? {
            if let image = cached(id, piece: piece, frame: frame) { return image }
            let previous = chain[id]
            let task = Task { [weak self] () -> CGImage? in
                _ = await previous?.value
                guard let self else { return nil }
                if let image = cached(id, piece: piece, frame: frame) { return image }
                let image = await player(id, piece: piece).image(atFrame: frame, scale: scale)
                if let image { remember(image, id: id, frame: frame) }
                return image
            }
            chain[id] = task
            return await task.value
        }

        /// For the live stage: the picture if it's drawn, else the last one of that piece (and start drawing it).
        public func frameNow(_ id: String, piece: HmmWebPiece, frame: Int) -> CGImage? {
            if let image = cached(id, piece: piece, frame: frame) { return image }
            let key = "\(id)#\(frame)"
            if !inFlight.contains(key) {
                inFlight.insert(key)
                Task { [weak self] in
                    _ = await self?.frame(id, piece: piece, frame: frame)
                    self?.inFlight.remove(key)
                    self?.onFrame?()
                }
            }
            return latest[id]
        }

        /// What the piece's page threw, for reports.
        public func errors(_ id: String) -> [String] {
            players[id]?.errors ?? []
        }

        /// Forgets every player and picture (a project closes, memory runs low).
        public func clear() {
            players.values.forEach { $0.unload() }
            players.removeAll()
            used.removeAll()
            ready.removeAll()
            latest.removeAll()
            chain.removeAll()
        }

        private func cached(_ id: String, piece: HmmWebPiece, frame: Int) -> CGImage? {
            if let player = players[id], player.piece != piece {
                player.unload()
                players[id] = nil
                ready[id] = nil
                latest[id] = nil
                return nil
            }
            return ready[id]?[frame]
        }

        private func player(_ id: String, piece: HmmWebPiece) -> HmmWebPlayer {
            used.removeAll { $0 == id }
            used.append(id)
            if let known = players[id] { return known }
            let player = HmmWebPlayer(piece: piece)
            players[id] = player
            while used.count > livePlayers, let oldest = used.first {
                used.removeFirst()
                players[oldest]?.unload()
                players[oldest] = nil
            }
            return player
        }

        private func remember(_ image: CGImage, id: String, frame: Int) {
            var frames = ready[id] ?? [:]
            if frames.count >= 120, let far = frames.keys.max(by: { abs($0 - frame) < abs($1 - frame) }) { frames[far] = nil }
            frames[frame] = image
            ready[id] = frames
            latest[id] = image
        }
    }
#endif
