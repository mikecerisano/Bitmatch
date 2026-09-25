// UnreadableMediaMonitorTests.swift
// A blank disk image (no file system) is what a camera card looks like to a
// Mac without the camera maker's driver: Disk Arbitration sees the disk,
// nothing mounts. The monitor must raise a notice and clear it on eject.
import Foundation
import XCTest
@testable import BitMatch

@MainActor
final class UnreadableMediaMonitorTests: XCTestCase {
    private func hdiutil(_ arguments: [String], output: Bool = false) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        do { try process.run() } catch { return (-1, "") }
        process.waitUntilExit()
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, text)
    }

    /// Fails if the monitor stops registering the disk-appeared callback,
    /// or if `Media(description:)` stops reading the disk's properties.
    func testBlankCardRaisesANoticeAndEjectClearsIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bitmatch_blank_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("blank.dmg")
        guard hdiutil(["create", "-quiet", "-size", "8m", "-layout", "NONE", "-type", "UDIF", image.path]).0 == 0 else {
            throw XCTSkip("hdiutil could not create a blank image")
        }

        let monitor = UnreadableMediaMonitor()
        monitor.start()
        defer { monitor.stop() }

        let (status, attachOutput) = hdiutil(["attach", "-nomount", "-nobrowse", image.path])
        guard status == 0, let device = attachOutput.split(whereSeparator: \.isWhitespace).first.map(String.init) else {
            throw XCTSkip("hdiutil could not attach the blank image")
        }
        let bsdName = device.replacingOccurrences(of: "/dev/", with: "")
        var detached = false
        defer { if !detached { _ = hdiutil(["detach", "-quiet", "-force", device]) } }

        let raised = await waitUntil(timeout: .seconds(10)) { monitor.notices.contains { $0.id == bsdName } }
        XCTAssertTrue(raised, "no notice for \(bsdName); notices: \(monitor.notices.map(\.id))")
        XCTAssertEqual(monitor.notices.first { $0.id == bsdName }?.kind, .unknownFormat)

        _ = hdiutil(["detach", "-quiet", "-force", device])
        detached = true
        let cleared = await waitUntil(timeout: .seconds(10)) { !monitor.notices.contains { $0.id == bsdName } }
        XCTAssertTrue(cleared, "notice for \(bsdName) stayed after eject")
    }
}
