import Synchronization

/// A value tests write from engine callbacks, which may run on any thread.
final class Locked<Value: Sendable>: Sendable {
    private let storage: Mutex<Value>

    init(_ value: Value) { storage = Mutex(value) }

    var value: Value { storage.withLock { $0 } }

    func set(_ value: Value) { storage.withLock { $0 = value } }
}
