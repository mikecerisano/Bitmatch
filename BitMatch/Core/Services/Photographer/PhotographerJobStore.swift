import CoreData
import Foundation

enum PhotographerStoreError: Error, Equatable {
    case corruptRecord(UUID?)
    case persistentStoreUnavailable
}

@MainActor
protocol PhotographerJobStore {
    func jobs() throws -> [PhotographerJob]
    func save(_ job: PhotographerJob) throws
    func deleteJob(id: UUID) throws
    func presets() throws -> [PhotographerPreset]
    func save(_ preset: PhotographerPreset) throws
    func profiles() throws -> [RemoteDestinationProfile]
    func save(_ profile: RemoteDestinationProfile) throws
    func deleteProfile(id: UUID) throws
    func manifests() throws -> [RemoteManifest]
    func save(_ manifest: RemoteManifest) throws
    func deleteManifest(id: UUID) throws
    func queueItems() throws -> [RemoteQueueItem]
    func save(_ item: RemoteQueueItem) throws
    func deleteQueueItem(id: UUID) throws
    var isAvailable: Bool { get }
    func whenAvailable(_ action: @escaping () -> Void)
}

extension PhotographerJobStore {
    var isAvailable: Bool { true }
    func whenAvailable(_: @escaping () -> Void) {}
    func profiles() throws -> [RemoteDestinationProfile] { [] }
    func save(_: RemoteDestinationProfile) throws {}
    func deleteProfile(id _: UUID) throws {}
    func manifests() throws -> [RemoteManifest] { [] }
    func save(_: RemoteManifest) throws {}
    func deleteManifest(id _: UUID) throws {}
    func queueItems() throws -> [RemoteQueueItem] { [] }
    func save(_: RemoteQueueItem) throws {}
    func deleteQueueItem(id _: UUID) throws {}
}

@MainActor
final class CoreDataPhotographerJobStore: PhotographerJobStore {
    private enum Entity {
        static let job = "PhotographerJobRecord"
        static let preset = "PhotographerPresetRecord"
        static let profile = "RemoteDestinationProfileRecord"
        static let manifest = "RemoteManifestRecord"
        static let queueItem = "RemoteQueueItemRecord"
    }

    private let context: NSManagedObjectContext
    private let credentialStore: RemoteCredentialStore
    private let storeIsAvailable: () -> Bool
    private let registerWhenAvailable: (@escaping () -> Void) -> Void

    init(
        context: NSManagedObjectContext,
        credentialStore: RemoteCredentialStore = RemoteCredentialStore()
    ) {
        self.context = context
        self.credentialStore = credentialStore
        self.storeIsAvailable = { true }
        self.registerWhenAvailable = { _ in }
    }

    init(
        persistence: BitMatchPersistenceController,
        credentialStore: RemoteCredentialStore = RemoteCredentialStore()
    ) {
        self.context = persistence.container.viewContext
        self.credentialStore = credentialStore
        self.storeIsAvailable = { persistence.isStoreLoaded }
        self.registerWhenAvailable = { action in persistence.whenStoreReady(action) }
    }

    var isAvailable: Bool { storeIsAvailable() }

    func whenAvailable(_ action: @escaping () -> Void) {
        registerWhenAvailable(action)
    }

    func jobs() throws -> [PhotographerJob] {
        try requireStore()
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.job)
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        return try context.fetch(request).map { record in
            try decode(PhotographerJob.self, from: record)
        }
    }

    func save(_ job: PhotographerJob) throws {
        try requireStore()
        do {
            let record = try record(for: job.id, entityName: Entity.job)
            record.setValue(job.id, forKey: "id")
            record.setValue(job.updatedAt, forKey: "updatedAt")
            record.setValue(try encode(job), forKey: "payload")
            try saveIfNeeded()
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteJob(id: UUID) throws {
        try requireStore()
        if let record = try existingRecord(for: id, entityName: Entity.job) {
            context.delete(record)
        }
        try saveIfNeeded()
    }

    func presets() throws -> [PhotographerPreset] {
        try requireStore()
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.preset)
        return try context.fetch(request)
            .map { record in
                try decode(PhotographerPreset.self, from: record)
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    func save(_ preset: PhotographerPreset) throws {
        try requireStore()
        do {
            let record = try record(for: preset.id, entityName: Entity.preset)
            record.setValue(preset.id, forKey: "id")
            record.setValue(Date(), forKey: "updatedAt")
            record.setValue(try encode(preset), forKey: "payload")
            try saveIfNeeded()
        } catch {
            context.rollback()
            throw error
        }
    }

    func profiles() throws -> [RemoteDestinationProfile] {
        try requireStore()
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.profile)
        return try context.fetch(request)
            .map { record in try decode(RemoteDestinationProfile.self, from: record) }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    func save(_ profile: RemoteDestinationProfile) throws {
        try requireStore()
        do {
            let record = try record(for: profile.id, entityName: Entity.profile)
            record.setValue(profile.id, forKey: "id")
            record.setValue(Date(), forKey: "updatedAt")
            record.setValue(credentialStore.accountName(for: profile.id), forKey: "credentialAccount")
            record.setValue(try encode(profile), forKey: "payload")
            try saveIfNeeded()
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteProfile(id: UUID) throws {
        try requireStore()
        if let record = try existingRecord(for: id, entityName: Entity.profile) {
            context.delete(record)
        }
        try saveIfNeeded()
        try credentialStore.deleteCredential(for: id)
    }

    func manifests() throws -> [RemoteManifest] {
        try requireStore()
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.manifest)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return try context.fetch(request).map { record in
            try decode(RemoteManifest.self, from: record)
        }
    }

    func save(_ manifest: RemoteManifest) throws {
        try requireStore()
        do {
            let record = try record(for: manifest.id, entityName: Entity.manifest)
            record.setValue(manifest.id, forKey: "id")
            record.setValue(manifest.createdAt, forKey: "createdAt")
            record.setValue(try encode(manifest), forKey: "payload")
            try saveIfNeeded()
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteManifest(id: UUID) throws {
        try requireStore()
        if let record = try existingRecord(for: id, entityName: Entity.manifest) {
            context.delete(record)
        }
        try saveIfNeeded()
    }

    func queueItems() throws -> [RemoteQueueItem] {
        try requireStore()
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.queueItem)
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        return try context.fetch(request).map { record in
            try decode(RemoteQueueItem.self, from: record)
        }
    }

    func save(_ item: RemoteQueueItem) throws {
        try requireStore()
        do {
            let record = try record(for: item.id, entityName: Entity.queueItem)
            record.setValue(item.id, forKey: "id")
            record.setValue(item.updatedAt, forKey: "updatedAt")
            record.setValue(try encode(item), forKey: "payload")
            try saveIfNeeded()
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteQueueItem(id: UUID) throws {
        try requireStore()
        if let record = try existingRecord(for: id, entityName: Entity.queueItem) {
            context.delete(record)
        }
        try saveIfNeeded()
    }

    private func record(for id: UUID, entityName: String) throws -> NSManagedObject {
        if let record = try existingRecord(for: id, entityName: entityName) {
            return record
        }
        return NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
    }

    private func existingRecord(for id: UUID, entityName: String) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try context.fetch(request).first
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from record: NSManagedObject
    ) throws -> Value {
        let id = record.value(forKey: "id") as? UUID
        guard let id, let payload = record.value(forKey: "payload") as? Data else {
            throw PhotographerStoreError.corruptRecord(id)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(type, from: payload)
        } catch {
            throw PhotographerStoreError.corruptRecord(id)
        }
    }

    private func saveIfNeeded() throws {
        if context.hasChanges {
            try context.save()
        }
    }

    private func requireStore() throws {
        guard storeIsAvailable() else {
            throw PhotographerStoreError.persistentStoreUnavailable
        }
    }
}
