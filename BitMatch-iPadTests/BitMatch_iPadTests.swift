//
//  BitMatch_iPadTests.swift
//  BitMatch-iPadTests
//
//  Created by Mike Cerisano on 8/28/25.
//

import Testing
@testable import BitMatch_iPad

struct BitMatch_iPadTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test @MainActor func drivePickerDelegateIsRetainedWhilePresented() async throws {
        #if os(iOS)
        IOSDriverScanner.clearRetainedDrivePickerDelegateForTesting()
        _ = IOSDriverScanner.makeDrivePickerForTesting { _ in }
        #expect(IOSDriverScanner.hasRetainedDrivePickerDelegateForTesting)
        IOSDriverScanner.clearRetainedDrivePickerDelegateForTesting()
        #else
        #expect(true)
        #endif
    }

}
