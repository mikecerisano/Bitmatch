import CoreData

final class BitMatchPersistenceController {
    static let shared = BitMatchPersistenceController()

    let container: NSPersistentContainer
    private(set) var persistentStoreLoadError: Error?

    var isStoreLoaded: Bool {
        persistentStoreLoadError == nil && !container.persistentStoreCoordinator.persistentStores.isEmpty
    }

    init(inMemory: Bool = false, storeURL: URL? = nil, forcedStoreLoadError: Error? = nil) {
        container = NSPersistentContainer(name: "BitMatch")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else if let storeURL {
            container.persistentStoreDescriptions.first?.url = storeURL
        }

        if let forcedStoreLoadError {
            persistentStoreLoadError = forcedStoreLoadError
        } else {
            container.loadPersistentStores { [weak self] _, error in
                self?.persistentStoreLoadError = error
            }
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
