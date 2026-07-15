import CoreData

@MainActor
final class BitMatchPersistenceController {
    static let shared = BitMatchPersistenceController()

    let container: NSPersistentContainer
    private(set) var persistentStoreLoadError: Error?
    private var storeReadyObservers: [() -> Void] = []
    private var didStartStoreLoad = false

    var isStoreLoaded: Bool {
        persistentStoreLoadError == nil && !container.persistentStoreCoordinator.persistentStores.isEmpty
    }

    init(
        inMemory: Bool = false,
        storeURL: URL? = nil,
        forcedStoreLoadError: Error? = nil,
        deferStoreLoad: Bool = false
    ) {
        container = NSPersistentContainer(name: "BitMatch")
        if let description = container.persistentStoreDescriptions.first {
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true

            if inMemory {
                description.url = URL(fileURLWithPath: "/dev/null")
            } else if let storeURL {
                description.url = storeURL
            }
        }

        if let forcedStoreLoadError {
            persistentStoreLoadError = forcedStoreLoadError
        } else if !deferStoreLoad {
            loadPersistentStore()
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

    /// Begins a deferred initial load. Production construction starts loading
    /// immediately; the deferred form exists to exercise readiness callbacks.
    func loadPersistentStore() {
        guard !didStartStoreLoad, persistentStoreLoadError == nil else { return }
        didStartStoreLoad = true
        container.loadPersistentStores { [weak self] _, error in
            Task { @MainActor in
                self?.finishStoreLoad(error)
            }
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
