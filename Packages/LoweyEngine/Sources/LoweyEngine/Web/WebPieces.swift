import Foundation
import HmmWeb
import LoweyCore

public extension WebPiece {
    /// The kit's piece: the inline page, or the project's file or folder that `mediaURL` finds. Nil when there's nothing
    /// to play (no page, a missing file).
    func playable(mediaURL: (String) -> URL?) -> HmmWebPiece? {
        let kind: HmmWebPiece.Kind = kind == .lottie ? .lottie : .html
        let size = clampedSize
        if let source, !source.isEmpty {
            return HmmWebPiece(kind: kind, source: .inline(source), width: size.width, height: size.height)
        }
        guard let file, !file.isEmpty, let url = mediaURL(file) else { return nil }
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { return nil }
        let source: HmmWebPiece.Source = isFolder.boolValue
            ? .folder(url, entry: entry ?? "index.html")
            : .folder(url.deletingLastPathComponent(), entry: url.lastPathComponent)
        return HmmWebPiece(kind: kind, source: source, width: size.width, height: size.height)
    }
}

extension ExportSession {
    /// The piece object `id` plays, ready for the player.
    func webPiece(_ id: ObjectID) -> HmmWebPiece? {
        builder.document.scene.webPiece(id)?.playable(mediaURL: mediaURL)
    }
}
