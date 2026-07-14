import CoreData
import Foundation
import Testing
@testable import BitMatch

struct PhotographerJobStoreTests {
    @MainActor
    @Test func savedJobRoundTrips() throws {
        let (persistence, store) = makeStore()
        let job = makeJob(id: uuid(101), name: "Smith Wedding", updatedAt: date(200))

        try store.save(job)

        #expect(try store.jobs() == [job])
        _ = persistence
    }

    @MainActor
    @Test func deletingJobRemovesIt() throws {
        let (_, store) = makeStore()
        let job = makeJob(id: uuid(102), name: "Delete Me", updatedAt: date(200))
        try store.save(job)

        try store.deleteJob(id: job.id)

        #expect(try store.jobs().isEmpty)
    }

    @MainActor
    @Test func savingJobWithExistingIDUpdatesRecord() throws {
        let (_, store) = makeStore()
        let original = makeJob(id: uuid(103), name: "Original", updatedAt: date(200))
        var updated = original
        updated.jobName = "Updated"
        updated.updatedAt = date(300)

        try store.save(original)
        try store.save(updated)

        #expect(try store.jobs() == [updated])
    }

    @MainActor
    @Test func jobsAreSortedByUpdatedDateDescending() throws {
        let (_, store) = makeStore()
        let older = makeJob(id: uuid(104), name: "Older", updatedAt: date(200))
        let newer = makeJob(id: uuid(105), name: "Newer", updatedAt: date(300))

        try store.save(older)
        try store.save(newer)

        #expect(try store.jobs() == [newer, older])
    }

    @MainActor
    @Test func weddingPresetRoundTripsWithTwoRequiredLocalCopies() throws {
        let (_, store) = makeStore()
        let preset = makePreset(id: uuid(201), name: "Wedding", requiredLocalCopyCount: 2)

        try store.save(preset)

        let saved = try #require(store.presets().first)
        #expect(saved == preset)
        #expect(saved.requiredLocalCopyCount == 2)
    }

    @MainActor
    @Test func savingPresetWithExistingIDUpdatesRecord() throws {
        let (_, store) = makeStore()
        let original = makePreset(id: uuid(202), name: "Wedding", requiredLocalCopyCount: 2)
        var updated = original
        updated.name = "Updated Wedding"
        updated.requiredLocalCopyCount = 3

        try store.save(original)
        try store.save(updated)

        #expect(try store.presets() == [updated])
    }

    @MainActor
    @Test func presetsAreSortedByName() throws {
        let (_, store) = makeStore()
        let zulu = makePreset(id: uuid(203), name: "Zulu", requiredLocalCopyCount: 1)
        let alpha = makePreset(id: uuid(204), name: "Alpha", requiredLocalCopyCount: 2)

        try store.save(zulu)
        try store.save(alpha)

        #expect(try store.presets() == [alpha, zulu])
    }

    @MainActor
    @Test func malformedJobPayloadReportsCorruptRecordID() throws {
        let (persistence, store) = makeStore()
        let id = uuid(301)
        let record = NSEntityDescription.insertNewObject(
            forEntityName: "PhotographerJobRecord",
            into: persistence.container.viewContext
        )
        record.setValue(id, forKey: "id")
        record.setValue(date(200), forKey: "updatedAt")
        record.setValue(Data("not-json".utf8), forKey: "payload")
        try persistence.container.viewContext.save()

        #expect(throws: PhotographerStoreError.corruptRecord(id)) {
            try store.jobs()
        }
    }

    @MainActor
    @Test func malformedPresetPayloadReportsCorruptRecordID() throws {
        let (persistence, store) = makeStore()
        let id = uuid(302)
        let record = NSEntityDescription.insertNewObject(
            forEntityName: "PhotographerPresetRecord",
            into: persistence.container.viewContext
        )
        record.setValue(id, forKey: "id")
        record.setValue(date(200), forKey: "updatedAt")
        record.setValue(Data("not-json".utf8), forKey: "payload")
        try persistence.container.viewContext.save()

        #expect(throws: PhotographerStoreError.corruptRecord(id)) {
            try store.presets()
        }
    }

    @MainActor
    @Test func persistentStoreLoadFailureDoesNotCrashAndRepositoryFailsClosed() throws {
        let persistence = BitMatchPersistenceController(
            forcedStoreLoadError: NSError(domain: "StoreLoad", code: 1)
        )
        let store = CoreDataPhotographerJobStore(persistence: persistence)

        #expect(throws: PhotographerStoreError.persistentStoreUnavailable) {
            try store.jobs()
        }
        #expect(throws: PhotographerStoreError.persistentStoreUnavailable) {
            try store.save(makeJob(id: uuid(999), name: "Never Saved", updatedAt: date(200)))
        }
    }

    @MainActor
    private func makeStore() -> (BitMatchPersistenceController, CoreDataPhotographerJobStore) {
        let persistence = BitMatchPersistenceController(inMemory: true)
        return (
            persistence,
            CoreDataPhotographerJobStore(context: persistence.container.viewContext)
        )
    }

    private func makeJob(id: UUID, name: String, updatedAt: Date) -> PhotographerJob {
        PhotographerJob(
            id: id,
            eventDate: date(100),
            clientName: "Smith",
            jobName: name,
            eventType: .wedding,
            photographers: [],
            recipe: .wedding,
            requiredLocalCopyCount: 2,
            cardIngests: [],
            createdAt: date(150),
            updatedAt: updatedAt
        )
    }

    private func makePreset(
        id: UUID,
        name: String,
        requiredLocalCopyCount: Int
    ) -> PhotographerPreset {
        PhotographerPreset(
            id: id,
            name: name,
            eventType: .wedding,
            recipe: .wedding,
            requiredLocalCopyCount: requiredLocalCopyCount
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
    }
}
