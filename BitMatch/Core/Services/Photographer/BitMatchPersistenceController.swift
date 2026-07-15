import CoreData

@MainActor
final class BitMatchPersistenceController {
    static let shared = BitMatchPersistenceController()

    let container: NSPersistentContainer
    private(set) var persistentStoreLoadError: Error?
    private var storeReadyObservers: [() -> Void] = []

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
                Task { @MainActor in
                    self?.finishStoreLoad(error)
                }
            }
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    /// Calls `action` after an in-flight initial store load succeeds. If the
    /// store has already loaded, it runs immediately; failed loads stay closed.
    func whenStoreReady(_ action: @escaping () -> Void) {
        if isStoreLoaded {
            action()
        } else if persistentStoreLoadError == nil {
            storeReadyObservers.append(action)
        }
    }

    private func finishStoreLoad(_ error: Error?) {
        persistentStoreLoadError = error
        guard error == nil else {
            storeReadyObservers.removeAll()
            return
        }
        let observers = storeReadyObservers
        storeReadyObservers.removeAll()
        observers.forEach { $0() }
    }
}
