import CoreData
import Foundation

enum PhotographerStoreError: Error, Equatable {
    case corruptRecord(UUID)
}

@MainActor
protocol PhotographerJobStore {
    func jobs() throws -> [PhotographerJob]
    func save(_ job: PhotographerJob) throws
    func deleteJob(id: UUID) throws
    func presets() throws -> [PhotographerPreset]
    func save(_ preset: PhotographerPreset) throws
}

@MainActor
final class CoreDataPhotographerJobStore: PhotographerJobStore {
    private enum Entity {
        static let job = "PhotographerJobRecord"
        static let preset = "PhotographerPresetRecord"
    }

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func jobs() throws -> [PhotographerJob] {
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.job)
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        return try context.fetch(request).map { record in
            try decode(PhotographerJob.self, from: record)
        }
    }

    func save(_ job: PhotographerJob) throws {
        let record = try record(for: job.id, entityName: Entity.job)
        record.setValue(job.id, forKey: "id")
        record.setValue(job.updatedAt, forKey: "updatedAt")
        record.setValue(try encode(job), forKey: "payload")
        try saveIfNeeded()
    }

    func deleteJob(id: UUID) throws {
        if let record = try existingRecord(for: id, entityName: Entity.job) {
            context.delete(record)
        }
        try saveIfNeeded()
    }

    func presets() throws -> [PhotographerPreset] {
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
        let record = try record(for: preset.id, entityName: Entity.preset)
        record.setValue(preset.id, forKey: "id")
        record.setValue(Date(), forKey: "updatedAt")
        record.setValue(try encode(preset), forKey: "payload")
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
        let id = record.value(forKey: "id") as! UUID
        let payload = record.value(forKey: "payload") as! Data
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
}
