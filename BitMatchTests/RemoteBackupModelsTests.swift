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

    @Test func malformedChecksumEvidenceIsNotConstructedAsVerifiedEvidence() {
        let validDigest = String(repeating: "a", count: 64)
        let malformedDigests = [
            "",
            "not-a-checksum",
            String(repeating: "a", count: 63),
            String(repeating: "g", count: 64),
            " " + validDigest
        ]

        for digest in malformedDigests {
            #expect(RemoteVerificationEvidence(serverSHA256: digest) == nil)
            #expect(RemoteVerificationEvidence(readBackSHA256: digest) == nil)
            #expect(RemoteVerificationEvidence.sha256(digest).digest == nil)
            #expect(RemoteVerificationEvidence.readBackSHA256(digest).digest == nil)
        }
    }

    @Test func malformedDecodedChecksumEvidenceBecomesNone() throws {
        let encodedEvidence = Data(#"{"sha256":{"_0":"not-a-checksum"}}"#.utf8)

        let evidence = try JSONDecoder().decode(RemoteVerificationEvidence.self, from: encodedEvidence)

        #expect(evidence == .none)
    }
}
