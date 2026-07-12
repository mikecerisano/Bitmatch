import CryptoKit
import Foundation

final class DisposableTransferFixture {
    let source: URL
    let destinations: [URL]
    let manifest: [String: String]

    private let root: URL

    init(seed: UInt64, fileCount: Int, bytesPerFile: Int) throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("bitmatch-disposable-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("SOURCE", isDirectory: true)
        let mediaDirectory = source.appendingPathComponent("DCIM/100MEDIA", isDirectory: true)
        let emptySidecars = source.appendingPathComponent("EMPTY_SIDECARS", isDirectory: true)
        let destinations = ["DEST_A", "DEST_B"].map {
            root.appendingPathComponent($0, isDirectory: true)
        }

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent(".bitmatch-disposable-fixture"))
        try fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: emptySidecars, withIntermediateDirectories: true)
        for destination in destinations {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        }

        var manifest: [String: String] = [:]
        let metadataPath = ".camera-metadata"
        let metadata = Data("BitMatch disposable camera fixture\n".utf8)
        try metadata.write(to: source.appendingPathComponent(metadataPath))
        manifest[metadataPath] = Self.sha256(metadata)

        for fileIndex in 0..<fileCount {
            let relativePath = String(format: "DCIM/100MEDIA/MEDIA_%04d.bin", fileIndex)
            let bytes = (0..<bytesPerFile).map { byteIndex in
                UInt8(truncatingIfNeeded: (seed &+ UInt64(fileIndex) &+ UInt64(byteIndex)) & 0xff)
            }
            let data = Data(bytes)
            try data.write(to: source.appendingPathComponent(relativePath))
            manifest[relativePath] = Self.sha256(data)
        }

        self.root = root
        self.source = source
        self.destinations = destinations
        self.manifest = manifest
    }

    func cleanup() {
        guard root.standardizedFileURL.path.hasPrefix(
            FileManager.default.temporaryDirectory.standardizedFileURL.path
        ), FileManager.default.fileExists(
            atPath: root.appendingPathComponent(".bitmatch-disposable-fixture").path
        ) else { return }

        try? FileManager.default.removeItem(at: root)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
