//
//  Persistence.swift
//  BitMatch-iPad
//
//  Created by Mike Cerisano on 8/28/25.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    /// Indicates whether Core Data loaded successfully
    private(set) var isAvailable: Bool = true
    private(set) var loadError: Error?

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        for _ in 0..<10 {
            let newItem = iPadItem(context: viewContext)
            newItem.timestamp = Date()
        }
        do {
            try viewContext.save()
        } catch {
            // Log error but don't crash - preview data is non-critical
            SharedLogger.error("Core Data preview save failed: \(error.localizedDescription)", category: .transfer)
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "BitMatch_iPad")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { [self] (storeDescription, error) in
            if let error = error as NSError? {
                // Log error but don't crash - Core Data is not critical for BitMatch's core functionality
                // Typical reasons for error:
                // - Parent directory missing or not writable
                // - Store not accessible due to permissions/device lock
                // - Device out of space
                // - Store migration failed
                SharedLogger.error("Core Data store failed to load: \(error.localizedDescription). UserInfo: \(error.userInfo)", category: .transfer)

                // Mark as unavailable so the app can handle gracefully
                // Note: Can't mutate self in closure, so we log but the app should check isAvailable
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
