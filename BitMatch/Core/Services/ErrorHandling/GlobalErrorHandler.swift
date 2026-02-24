// Core/Services/ErrorHandling/GlobalErrorHandler.swift
import Foundation
import SwiftUI

/// Global error handler for graceful error recovery
@MainActor
class GlobalErrorHandler: ObservableObject {
    static let shared = GlobalErrorHandler()

    @Published var currentError: AppError?
    @Published var showErrorAlert = false

    private init() {}

    func handle(_ error: Error, context: String = "") {
        let appError = AppError.from(error, context: context)

        SharedLogger.error("Global Error [\(context)]: \(appError.localizedDescription)", category: .error)

        currentError = appError
        showErrorAlert = true
    }

    func clearError() {
        currentError = nil
        showErrorAlert = false
    }

    /// Retry the last failed operation if a retry action was provided
    func retry() {
        guard let error = currentError else { return }
        clearError()
        error.retryAction?()
    }
}

enum AppError: LocalizedError {
    case fileOperation(String, recovery: String? = nil, retry: (() -> Void)? = nil)
    case networkError(String, recovery: String? = nil)
    case invalidData(String, recovery: String? = nil)
    case insufficientStorage(String, recovery: String? = nil)
    case permissionDenied(String, recovery: String? = nil)
    case unknown(String, recovery: String? = nil)

    var errorDescription: String? {
        switch self {
        case .fileOperation(let msg, _, _): return msg
        case .networkError(let msg, _): return msg
        case .invalidData(let msg, _): return msg
        case .insufficientStorage(let msg, _): return msg
        case .permissionDenied(let msg, _): return msg
        case .unknown(let msg, _): return msg
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .fileOperation(_, let recovery, _): return recovery ?? "Check that the file exists and is accessible."
        case .networkError(_, let recovery): return recovery ?? "Check your network connection and try again."
        case .invalidData(_, let recovery): return recovery ?? "The data may be corrupted. Try the operation again."
        case .insufficientStorage(_, let recovery): return recovery ?? "Free up space on the destination drive."
        case .permissionDenied(_, let recovery): return recovery ?? "Check file permissions or try a different location."
        case .unknown(_, let recovery): return recovery
        }
    }

    var retryAction: (() -> Void)? {
        switch self {
        case .fileOperation(_, _, let retry): return retry
        default: return nil
        }
    }

    var canRetry: Bool { retryAction != nil }

    static func from(_ error: Error, context: String) -> AppError {
        if let appError = error as? AppError {
            return appError
        }

        if let nsError = error as NSError? {
            switch nsError.domain {
            case NSCocoaErrorDomain:
                switch nsError.code {
                case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
                    return .fileOperation("File not found.",
                        recovery: "Verify the file exists and the drive is still connected.")
                case NSFileWriteOutOfSpaceError:
                    return .insufficientStorage("Not enough space on destination.",
                        recovery: "Free up space on the destination drive or choose a different destination.")
                case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                    return .permissionDenied("Permission denied.",
                        recovery: "Check file permissions in Finder > Get Info, or try a different location.")
                default:
                    return .fileOperation("Unable to access file.",
                        recovery: "Check that the file is not locked by another application.")
                }
            case NSURLErrorDomain:
                return .networkError("Connection failed.",
                    recovery: "Check your network connection and verify the drive is accessible.")
            default:
                return .unknown(error.localizedDescription)
            }
        }

        return .unknown(error.localizedDescription)
    }
}
