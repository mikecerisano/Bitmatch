import Foundation
import Testing
@testable import BitMatch

@MainActor
struct RemoteBackupCoordinatorTests {
    @Test func copyingCardCannotCreateRemoteManifest() throws {
        let fixture = try CoordinatorFixture(localState: .copying)

        #expect(throws: RemoteBackupError.localArtifactNotVerified) {
            try fixture.coordinator.queueRemoteBackup(
                for: fixture.card.id,
                in: fixture.job.id,
                results: fixture.rows
            )
        }
        #expect(fixture.store.storedManifests.isEmpty)
        #expect(fixture.store.storedQueueItems.isEmpty)
    }

    @Test func failedCardCannotCreateRemoteManifest() throws {
        let fixture = try CoordinatorFixture(localState: .issues)

        #expect(throws: RemoteBackupError.localArtifactNotVerified) {
            try fixture.coordinator.queueRemoteBackup(
                for: fixture.card.id,
                in: fixture.job.id,
                results: fixture.rows
            )
        }
    }

    @Test func queueBookmarkIsCreatedFromVerifiedDestinationPackageNeverSourceCard() throws {
        let fixture = try CoordinatorFixture()

        let items = try fixture.coordinator.queueRemoteBackup(
            for: fixture.card.id,
            in: fixture.job.id,
            results: fixture.rows
        )

        let item = try #require(items.first)
        let savedBookmarkData = try fixture.bookmarks.data(for: item.localArtifactBookmarkReference)
        let bookmarkData = try #require(savedBookmarkData)
        #expect(String(decoding: bookmarkData, as: UTF8.self) == fixture.destinationPackage.path)
        #expect(String(decoding: bookmarkData, as: UTF8.self) != fixture.sourceCard.path)
        #expect(item.localArtifactRelativePath.components == ["DCIM", "A.ARW"])
    }

    @Test func resolverRejectsArtifactWhoseChecksumNoLongerMatchesManifest() async throws {
        let fixture = try CoordinatorFixture(checksum: String(repeating: "a", count: 64))
        let item = try #require(try fixture.coordinator.queueRemoteBackup(
            for: fixture.card.id,
            in: fixture.job.id,
            results: fixture.rows
        ).first)

        fixture.checksum = String(repeating: "b", count: 64)

        await #expect(throws: RemoteBackupError.localArtifactNotVerified) {
            _ = try await fixture.coordinator.resolveLocalArtifact(for: item)
        }
    }
}

@MainActor
private final class CoordinatorFixture {
    let sourceCard = URL(fileURLWithPath: "/Volumes/CARD")
    let destinationPackage = URL(fileURLWithPath: "/Volumes/Archive/Job/Card-001")
    let store: CoordinatorStore
    let bookmarks = CoordinatorBookmarkStore()
    var checksum: String
    let job: PhotographerJob
    let card: CardIngest
    let rows: [ResultRow]
    let coordinator: RemoteBackupCoordinator

    init(
        localState: PhotographerLocalState = .locallySafe,
        checksum: String = String(repeating: "a", count: 64)
    ) throws {
        self.checksum = checksum
        let card = CardIngest(
            id: UUID(),
            provenance: CardProvenance(
                photographerID: UUID(), photographerName: "Mike", cameraName: "Sony", cardNumber: 1,
                preliminaryFingerprint: "preliminary", confirmedFingerprint: "confirmed"
            ),
            sourceDisplayName: "CARD",
            renderedRelativePath: "Job/Card-001",
            localState: localState,
            startedAt: Date(timeIntervalSince1970: 1),
            locallySafeAt: localState == .locallySafe ? Date(timeIntervalSince1970: 2) : nil,
            fileCount: 1,
            totalBytes: 3,
            verifiedDestinationCount: localState == .locallySafe ? 1 : 0
        )
        self.card = card
        let profile = RemoteDestinationProfile(
            id: UUID(), name: "Archive", host: "archive.example.test", port: 22, username: "mike",
            root: try RemoteRelativePath(components: ["Backups"]), verificationMode: .sha256
        )
        self.job = PhotographerJob(
            id: UUID(), eventDate: .now, clientName: "Smith", jobName: "Wedding", eventType: .wedding,
            photographers: [], recipe: .wedding, requiredLocalCopyCount: 1, cardIngests: [card],
            remoteBackupConfiguration: .init(isEnabled: true, destinationProfileID: profile.id),
            createdAt: .now, updatedAt: .now
        )
        self.rows = [ResultRow(
            path: sourceCard.appendingPathComponent("DCIM/A.ARW").path,
            status: "✅ Verified", size: 3, checksum: checksum, destination: "Archive",
            destinationPath: destinationPackage.appendingPathComponent("DCIM/A.ARW").path
        )]
        self.store = CoordinatorStore(jobs: [job], profiles: [profile])
        self.coordinator = RemoteBackupCoordinator(
            store: store,
            bookmarkStore: bookmarks,
            makeBookmark: { Data($0.path.utf8) },
            resolveBookmark: { URL(fileURLWithPath: String(decoding: $0, as: UTF8.self)) },
            fileSize: { _ in 3 },
            sha256: { [weak self] _ in self?.checksum ?? "" },
            now: { Date(timeIntervalSince1970: 3) }
        )
    }
}

@MainActor
private final class CoordinatorStore: PhotographerJobStore {
    var storedJobs: [PhotographerJob]
    var storedProfiles: [RemoteDestinationProfile]
    var storedManifests: [RemoteManifest] = []
    var storedQueueItems: [RemoteQueueItem] = []

    init(jobs: [PhotographerJob], profiles: [RemoteDestinationProfile]) {
        storedJobs = jobs
        storedProfiles = profiles
    }

    func jobs() throws -> [PhotographerJob] { storedJobs }
    func save(_ job: PhotographerJob) throws { storedJobs = [job] }
    func deleteJob(id: UUID) throws { storedJobs.removeAll { $0.id == id } }
    func presets() throws -> [PhotographerPreset] { [] }
    func save(_: PhotographerPreset) throws {}
    func profiles() throws -> [RemoteDestinationProfile] { storedProfiles }
    func save(_: RemoteDestinationProfile) throws {}
    func deleteProfile(id _: UUID) throws {}
    func manifests() throws -> [RemoteManifest] { storedManifests }
    func save(_ manifest: RemoteManifest) throws { storedManifests.append(manifest) }
    func deleteManifest(id: UUID) throws { storedManifests.removeAll { $0.id == id } }
    func queueItems() throws -> [RemoteQueueItem] { storedQueueItems }
    func save(_ item: RemoteQueueItem) throws { storedQueueItems.append(item) }
    func deleteQueueItem(id: UUID) throws { storedQueueItems.removeAll { $0.id == id } }
}

private final class CoordinatorBookmarkStore: RemoteArtifactBookmarkStore {
    private var values: [String: Data] = [:]

    func save(_ data: Data, for reference: String) throws { values[reference] = data }
    func data(for reference: String) throws -> Data? { values[reference] }
    func remove(reference: String) throws { values.removeValue(forKey: reference) }
}
