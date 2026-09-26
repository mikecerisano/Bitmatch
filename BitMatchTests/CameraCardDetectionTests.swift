import XCTest
@testable import BitMatch

/// Lifecycle coverage for camera-card volume monitoring: typed URL
/// extraction plus observer-token ownership (block observers must be
/// removed by token, or restarts accumulate duplicate callbacks).
final class CameraCardDetectionTests: XCTestCase {
#if os(macOS)
    func testVolumeURLPrefersTypedKey() {
        let url = URL(fileURLWithPath: "/Volumes/EOS_DIGITAL")
        let note = Notification(
            name: NSWorkspace.didMountNotification,
            object: nil,
            userInfo: [NSWorkspace.volumeURLUserInfoKey: url]
        )
        XCTAssertEqual(VolumeMonitor.volumeURL(from: note), url)
    }

    func testVolumeURLBridgesNSURL() {
        let nsURL = NSURL(fileURLWithPath: "/Volumes/EOS_DIGITAL")
        let note = Notification(
            name: NSWorkspace.didMountNotification,
            object: nil,
            userInfo: [NSWorkspace.volumeURLUserInfoKey: nsURL]
        )
        XCTAssertEqual(VolumeMonitor.volumeURL(from: note), nsURL as URL)
    }

    func testVolumeURLFallsBackToDevicePath() {
        let note = Notification(
            name: NSWorkspace.didMountNotification,
            object: nil,
            userInfo: ["NSDevicePath": "/Volumes/EOS_DIGITAL"]
        )
        XCTAssertEqual(
            VolumeMonitor.volumeURL(from: note),
            URL(fileURLWithPath: "/Volumes/EOS_DIGITAL")
        )
    }

    func testVolumeURLNilWithoutPayload() {
        let note = Notification(name: NSWorkspace.didMountNotification, object: nil, userInfo: nil)
        XCTAssertNil(VolumeMonitor.volumeURL(from: note))
    }

    @MainActor
    func testStopRemovesObserversAndRestartDoesNotDuplicate() {
        var mountCount = 0
        let monitor = VolumeMonitor { event in
            if case .mounted = event.type { mountCount += 1 }
        }
        // A private center: real volumes mounted by other tests (exFAT disk
        // images) must not add to the count.
        let center = NotificationCenter()
        monitor.eventCenter = center
        func postMount() {
            center.post(
                name: NSWorkspace.didMountNotification,
                object: nil,
                userInfo: [NSWorkspace.volumeURLUserInfoKey: URL(fileURLWithPath: "/Volumes/TESTCARD")]
            )
            // Block observers run on the main queue; pump it.
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        }

        monitor.startMonitoring()
        postMount()
        XCTAssertEqual(mountCount, 1)

        monitor.stopMonitoring()
        postMount()
        XCTAssertEqual(mountCount, 1, "stopped monitor must not receive events")

        monitor.startMonitoring()
        postMount()
        XCTAssertEqual(mountCount, 2, "restarted monitor must receive exactly one event per post")

        monitor.stopMonitoring()
    }
#endif
}
