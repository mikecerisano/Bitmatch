import Foundation

/// Polls `condition` until it holds or `timeout` elapses, and returns
/// whether it held. Use this instead of a fixed sleep whenever a test is
/// waiting for something to happen: it returns as soon as the condition is
/// true, and a generous timeout only costs time when the test is failing.
///
/// A fixed sleep is still right when the wait is part of the scenario
/// (simulated slow work) or when the test asserts that something does
/// *not* happen within a window; this helper cannot express either.
///
/// Runs on the caller's actor, so a `@MainActor` test can read main-actor
/// state in `condition` directly.
@discardableResult
func waitUntil(
    timeout: Duration = .seconds(2),
    pollInterval: Duration = .milliseconds(10),
    isolation: isolated (any Actor)? = #isolation,
    _ condition: () async throws -> Bool
) async rethrows -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline, !Task.isCancelled {
        if try await condition() { return true }
        try? await Task.sleep(for: pollInterval)
    }
    return try await condition()
}
