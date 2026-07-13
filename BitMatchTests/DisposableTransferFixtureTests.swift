import Foundation
import Testing

struct DisposableTransferFixtureTests {

    @Test
    func identicalSeedsCreateIdenticalManifest() throws {
        let left = try DisposableTransferFixture(seed: 42, fileCount: 3, bytesPerFile: 1_024)
        let right = try DisposableTransferFixture(seed: 42, fileCount: 3, bytesPerFile: 1_024)
        defer {
            left.cleanup()
            right.cleanup()
        }

        #expect(left.manifest == right.manifest)
    }

    @Test
    func differentSeedsCreateDifferentManifest() throws {
        let left = try DisposableTransferFixture(seed: 42, fileCount: 3, bytesPerFile: 1_024)
        let right = try DisposableTransferFixture(seed: 43, fileCount: 3, bytesPerFile: 1_024)
        defer {
            left.cleanup()
            right.cleanup()
        }

        #expect(left.manifest != right.manifest)
    }

    @Test
    func createsCameraLayoutWithHiddenFileAndEmptyDirectory() throws {
        let fixture = try DisposableTransferFixture(seed: 42, fileCount: 3, bytesPerFile: 1_024)
        defer { fixture.cleanup() }
        let fileManager = FileManager.default

        var isDirectory: ObjCBool = false
        #expect(fileManager.fileExists(
            atPath: fixture.source.appendingPathComponent(".camera-metadata").path,
            isDirectory: &isDirectory
        ))
        #expect(!isDirectory.boolValue)

        let mediaDirectory = fixture.source.appendingPathComponent("DCIM/100MEDIA", isDirectory: true)
        #expect(fileManager.fileExists(atPath: mediaDirectory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)

        let emptyDirectory = fixture.source.appendingPathComponent("EMPTY_SIDECARS", isDirectory: true)
        #expect(fileManager.fileExists(atPath: emptyDirectory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(try fileManager.contentsOfDirectory(atPath: emptyDirectory.path).isEmpty)
    }

    @Test
    func cleanupRefusesRootWithoutDisposableMarker() throws {
        let fixture = try DisposableTransferFixture(seed: 42, fileCount: 1, bytesPerFile: 16)
        let root = fixture.source.deletingLastPathComponent()
        let marker = root.appendingPathComponent(".bitmatch-disposable-fixture")
        try FileManager.default.removeItem(at: marker)

        fixture.cleanup()

        #expect(FileManager.default.fileExists(atPath: root.path))

        try Data().write(to: marker)
        fixture.cleanup()
    }
}
