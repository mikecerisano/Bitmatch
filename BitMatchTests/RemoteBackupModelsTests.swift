import Foundation
import Testing
@testable import BitMatch

struct RemoteBackupModelsTests {
    @Test func relativePathRejectsParentTraversalComponent() {
        #expect(throws: RemotePathError.unsafeComponent("..")) {
            _ = try RemoteRelativePath(components: ["Job", "..", "Card-001"])
        }
    }

    @Test func manifestRejectsPortableNameCollisions() throws {
        let upper = RemoteManifestEntry(
            id: UUID(),
            relativePath: try RemoteRelativePath(components: ["Job", "CARD-001"]),
            byteCount: 10,
            sha256: "a"
        )
        let lower = RemoteManifestEntry(
            id: UUID(),
            relativePath: try RemoteRelativePath(components: ["job", "card-001"]),
            byteCount: 10,
            sha256: "b"
        )

        #expect(throws: RemoteManifestError.portableNameCollision("job/card-001")) {
            _ = try RemoteManifest(
                id: UUID(),
                jobID: UUID(),
                cardIngestID: UUID(),
                destinationProfileID: UUID(),
                packageRelativePath: try RemoteRelativePath(components: ["Job"]),
                entries: [upper, lower],
                createdAt: Date()
            )
        }
    }
}
