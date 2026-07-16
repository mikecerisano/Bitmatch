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

    @Test func resolverScopesAccessUntilItsLeaseIsReleased() async throws {
        let fixture = try CoordinatorFixture()
        let item = try #require(try fixture.coordinator.queueRemoteBackup(for: fixture.card.id, in: fixture.job.id, results: fixture.rows).first)

        let lease = try await fixture.coordinator.resolveLocalArtifact(for: item)
        #expect(fixture.scopeStarts == 1)
        #expect(fixture.scopeStops == 0)
        lease.release()
        lease.release()
        #expect(fixture.scopeStops == 1)
    }

    @Test func resolverStopsScopeWhenArtifactValidationFails() async throws {
        let fixture = try CoordinatorFixture(checksum: String(repeating: "a", count: 64))
        let item = try #require(try fixture.coordinator.queueRemoteBackup(for: fixture.card.id, in: fixture.job.id, results: fixture.rows).first)
        fixture.checksum = String(repeating: "b", count: 64)

        await #expect(throws: RemoteBackupError.localArtifactNotVerified) {
            _ = try await fixture.coordinator.resolveLocalArtifact(for: item)
        }
        #expect(fixture.scopeStarts == 1)
        #expect(fixture.scopeStops == 1)
    }

    @Test func resolverRejectsSymlinkThatEscapesTheBookmarkedPackage() async throws {
        let fixture = try CoordinatorFixture()
        let item = try #require(try fixture.coordinator.queueRemoteBackup(for: fixture.card.id, in: fixture.job.id, results: fixture.rows).first)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: outside.appendingPathComponent("A.ARW").path, contents: Data([0]))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("DCIM"), withDestinationURL: outside)
        try fixture.bookmarks.save(Data(root.path.utf8), for: item.localArtifactBookmarkReference)

        await #expect(throws: RemoteBackupError.localArtifactNotVerified) {
            _ = try await fixture.coordinator.resolveLocalArtifact(for: item)
        }
        #expect(fixture.scopeStarts == 1)
        #expect(fixture.scopeStops == 1)
    }

    @Test func partialItemSaveRollsBackAllItemsManifestAndBookmark() throws {
        let fixture = try CoordinatorFixture(fileCount: 2)
        fixture.store.failSavingItemAtAttempt = 2

        #expect(throws: CoordinatorStoreError.forcedSaveFailure) {
            try fixture.coordinator.queueRemoteBackup(for: fixture.card.id, in: fixture.job.id, results: fixture.rows)
        }
        #expect(fixture.store.storedQueueItems.isEmpty)
        #expect(fixture.store.storedManifests.isEmpty)
        #expect(fixture.bookmarks.isEmpty)
    }
}

@MainActor
private final class CoordinatorFixture {
    let sourceCard = URL(fileURLWithPath: "/Volumes/CARD")
    let destinationPackage = URL(fileURLWithPath: "/Volumes/Archive/Job/Card-001")
    let store: CoordinatorStore
    let bookmarks = CoordinatorBookmarkStore()
    var checksum: String
    var scopeStarts = 0
    var scopeStops = 0
    let job: PhotographerJob
    let card: CardIngest
    let rows: [ResultRow]
    let coordinator: RemoteBackupCoordinator

    init(
        localState: PhotographerLocalState = .locallySafe,
        checksum: String = String(repeating: "a", count: 64),
        fileCount: Int = 1
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
            fileCount: fileCount,
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
        self.rows = (0..<fileCount).map { index in
            let name = index == 0 ? "A.ARW" : "B.ARW"
            return ResultRow(
                path: sourceCard.appendingPathComponent("DCIM/\(name)").path,
                status: "✅ Verified", size: 3, checksum: checksum, destination: "Archive",
                destinationPath: destinationPackage.appendingPathComponent("DCIM/\(name)").path
            )
        }
        self.store = CoordinatorStore(jobs: [job], profiles: [profile])
        self.coordinator = RemoteBackupCoordinator(
            store: store,
            bookmarkStore: bookmarks,
            makeBookmark: { Data($0.path.utf8) },
            resolveBookmark: { URL(fileURLWithPath: String(decoding: $0, as: UTF8.self)) },
            fileSize: { _ in 3 },
            sha256: { [weak self] _ in self?.checksum ?? "" },
            startSecurityScope: { [weak self] _ in self?.recordScopeStart() ?? false },
            stopSecurityScope: { [weak self] _ in self?.recordScopeStop() },
            now: { Date(timeIntervalSince1970: 3) }
        )
    }

    private func recordScopeStart() -> Bool { scopeStarts += 1; return true }
    private func recordScopeStop() { scopeStops += 1 }
}

@MainActor
private final class CoordinatorStore: PhotographerJobStore {
    var storedJobs: [PhotographerJob]
    var storedProfiles: [RemoteDestinationProfile]
    var storedManifests: [RemoteManifest] = []
    var storedQueueItems: [RemoteQueueItem] = []
    var failSavingItemAtAttempt: Int?
    private var itemSaveAttempts = 0

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
    func save(_ item: RemoteQueueItem) throws {
        itemSaveAttempts += 1
        if itemSaveAttempts == failSavingItemAtAttempt { throw CoordinatorStoreError.forcedSaveFailure }
        storedQueueItems.append(item)
    }
    func deleteQueueItem(id: UUID) throws { storedQueueItems.removeAll { $0.id == id } }
}

private final class CoordinatorBookmarkStore: RemoteArtifactBookmarkStore {
    private var values: [String: Data] = [:]
    var isEmpty: Bool { values.isEmpty }

    func save(_ data: Data, for reference: String) throws { values[reference] = data }
    func data(for reference: String) throws -> Data? { values[reference] }
    func remove(reference: String) throws { values.removeValue(forKey: reference) }
}

private enum CoordinatorStoreError: Error { case forcedSaveFailure }
