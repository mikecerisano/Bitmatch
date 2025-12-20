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

        // Log error via shared logger
        SharedLogger.error("Global Error [\(context)]: \(appError.localizedDescription ?? "Unknown")", category: .error)

        // Show user-friendly error
        currentError = appError
        showErrorAlert = true
    }
    
    func clearError() {
        currentError = nil
        showErrorAlert = false
    }
}

enum AppError: LocalizedError {
    case fileOperation(String)
    case networkError(String)
    case invalidData(String)
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .fileOperation(let msg): return "File operation failed: \(msg)"
        case .networkError(let msg): return "Network error: \(msg)"
        case .invalidData(let msg): return "Invalid data: \(msg)"
        case .unknown(let msg): return "Unexpected error: \(msg)"
        }
    }
    
    static func from(_ error: Error, context: String) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        
        // Convert common system errors to user-friendly messages
        if let nsError = error as NSError? {
            switch nsError.domain {
            case NSCocoaErrorDomain:
                return .fileOperation("Unable to access file. Check permissions.")
            case NSURLErrorDomain:
                return .networkError("Connection failed. Check your internet connection.")
            default:
                return .unknown("\(error.localizedDescription)")
            }
        }
        
        return .unknown("\(error.localizedDescription)")
    }
}