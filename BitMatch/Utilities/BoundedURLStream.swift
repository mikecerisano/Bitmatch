import Foundation

struct BoundedURLStream {
    let stream: AsyncThrowingStream<URL, Error>
    let release: @Sendable () -> Void
}

func makeBoundedFileURLStream(at rootURL: URL, capacity: Int = 512) -> BoundedURLStream {
    let sema = DispatchSemaphore(value: capacity)

    let stream = AsyncThrowingStream<URL, Error> { continuation in
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]

        let t = Task.detached(priority: .userInitiated) {
            guard let en = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continuation.finish(); return }

            // Use ObjC-style iteration to avoid Swift 6 Sequence bridging issues.
            while let obj = en.nextObject() {
                if Task.isCancelled { break }
                guard let url = obj as? URL else { continue }
                autoreleasepool {
                    do {
                        let rv = try url.resourceValues(forKeys: Set(keys))
                        if rv.isSymbolicLink == true { /* skip */ }
                        else if rv.isRegularFile == true {
                            sema.wait()
                            continuation.yield(url)
                        }
                    } catch { /* ignore and continue */ }
                }
            }
            continuation.finish()
        }

        continuation.onTermination = { _ in
            t.cancel()
            for _ in 0..<capacity { sema.signal() } // unblock any waiters
        }
    }

    return BoundedURLStream(stream: stream, release: { sema.signal() })
}
