import XCTest
@testable import BitMatch

@MainActor
final class ErrorHandlingTests: XCTestCase {
    var handler: GlobalErrorHandler!

    override func setUp() {
        super.setUp()
        handler = GlobalErrorHandler.shared
        handler.clearError()
    }

    override func tearDown() {
        handler.clearError()
        super.tearDown()
    }

    // MARK: - GlobalErrorHandler

    func testHandleSetsCurrentError() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        handler.handle(error, context: "test")
        XCTAssertNotNil(handler.currentError)
        XCTAssertTrue(handler.showErrorAlert)
    }

    func testClearResetsState() {
        handler.handle(NSError(domain: "test", code: 0), context: "test")
        handler.clearError()
        XCTAssertNil(handler.currentError)
        XCTAssertFalse(handler.showErrorAlert)
    }

    func testRetryCallsAction() {
        var retryCalled = false
        let error = AppError.fileOperation("Failed", recovery: "Try again", retry: { retryCalled = true })
        handler.currentError = error
        handler.showErrorAlert = true
        handler.retry()
        XCTAssertTrue(retryCalled)
        XCTAssertNil(handler.currentError)
    }

    // MARK: - AppError Properties

    func testFileOperationDescription() {
        let error = AppError.fileOperation("Copy failed")
        XCTAssertEqual(error.errorDescription, "Copy failed")
    }

    func testRecoverySuggestion() {
        let error = AppError.fileOperation("Failed", recovery: "Check disk")
        XCTAssertEqual(error.recoverySuggestion, "Check disk")
    }

    func testDefaultRecoverySuggestion() {
        let error = AppError.networkError("Timeout")
        XCTAssertNotNil(error.recoverySuggestion)
    }

    func testCanRetry() {
        let retryable = AppError.fileOperation("Failed", recovery: nil, retry: {})
        XCTAssertTrue(retryable.canRetry)

        let notRetryable = AppError.networkError("Timeout")
        XCTAssertFalse(notRetryable.canRetry)
    }

    // MARK: - Error Conversion

    func testConvertFileNotFound() {
        let nsError = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        let appError = AppError.from(nsError, context: "test")
        switch appError {
        case .fileOperation(let msg, _, _):
            XCTAssertTrue(msg.contains("not found"))
        default:
            XCTFail("Expected fileOperation error")
        }
    }

    func testConvertOutOfSpace() {
        let nsError = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        let appError = AppError.from(nsError, context: "test")
        switch appError {
        case .insufficientStorage:
            break // expected
        default:
            XCTFail("Expected insufficientStorage error")
        }
    }

    func testConvertPermissionDenied() {
        let nsError = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
        let appError = AppError.from(nsError, context: "test")
        switch appError {
        case .permissionDenied:
            break // expected
        default:
            XCTFail("Expected permissionDenied error")
        }
    }

    func testConvertNetworkError() {
        let nsError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        let appError = AppError.from(nsError, context: "test")
        switch appError {
        case .networkError:
            break // expected
        default:
            XCTFail("Expected networkError")
        }
    }

    func testConvertUnknownDomain() {
        let nsError = NSError(domain: "com.custom.error", code: 42)
        let appError = AppError.from(nsError, context: "test")
        switch appError {
        case .unknown:
            break // expected
        default:
            XCTFail("Expected unknown error")
        }
    }

    func testPassthroughAppError() {
        let original = AppError.invalidData("Bad data", recovery: "Fix it")
        let converted = AppError.from(original, context: "test")
        switch converted {
        case .invalidData(let msg, _):
            XCTAssertEqual(msg, "Bad data")
        default:
            XCTFail("Should pass through AppError unchanged")
        }
    }

    // MARK: - All Error Types Have Descriptions

    func testAllTypesHaveDescriptions() {
        let errors: [AppError] = [
            .fileOperation("test"),
            .networkError("test"),
            .invalidData("test"),
            .insufficientStorage("test"),
            .permissionDenied("test"),
            .unknown("test")
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Missing description for \(error)")
        }
    }
}
