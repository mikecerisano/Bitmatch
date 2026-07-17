//
//  BitMatchUITestsLaunchTests.swift
//  BitMatchUITests
//
//  Created by Mike Cerisano on 8/17/25.
//

import XCTest

final class BitMatchUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--interface-lab"]
        app.launch()

        XCTAssertTrue(app.staticTexts["INTERFACE LAB · NO FILE ACCESS"].waitForExistence(timeout: 5))
    }
}
