// Core/Services/OperationResumeService.swift
import Foundation

#if os(macOS)
import AppKit
#endif

final class OperationResumeService {
    
    typealias ResumeHandler = (OperationStateManager.PersistedOperation) -> Void
    
    static func checkForInterruptedOperations(onResume: @escaping ResumeHandler) {
        if let resumeInfo = OperationStateManager.getResumeInfo() {
            // Show dialog to user about resuming
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showResumeDialog(resumeInfo, onResume: onResume)
            }
        }
    }
    
    private static func showResumeDialog(_ resumeInfo: OperationStateManager.ResumeInfo, onResume: @escaping ResumeHandler) {
        #if os(macOS)
        let alert = NSAlert()
        alert.messageText = "Resume Previous Operation?"
        alert.informativeText = """
            Found an interrupted operation:
            • Started: \(resumeInfo.operation.startTime.formatted())
            • Progress: \(Int(resumeInfo.estimatedProgress * 100))% complete
            • Files processed: \(resumeInfo.operation.processedCount) of \(resumeInfo.operation.totalCount)
            
            Would you like to resume?
            """
        alert.addButton(withTitle: "Resume")
        alert.addButton(withTitle: "Discard")
        
        if alert.runModal() == .alertFirstButtonReturn {
            onResume(resumeInfo.operation)
        } else {
            // Clear the saved state
            OperationStateManager.clearState(for: resumeInfo.operation.id)
        }
        #else
        // On iOS, automatically resume (or implement a different UI approach)
        // For now, auto-resume to maintain functionality
        onResume(resumeInfo.operation)
        #endif
    }
    
    @MainActor
    static func prepareResumeData(
        operation: OperationStateManager.PersistedOperation,
        fileSelectionViewModel: FileSelectionViewModel,
        progressViewModel: ProgressViewModel,
        verificationMode: inout VerificationMode
    ) -> (jobID: UUID, jobStart: Date) {
        
        // Restore file selections
        if operation.mode == "copy" {
            fileSelectionViewModel.sourceURL = operation.sourceURL
            fileSelectionViewModel.destinationURLs = operation.destinationURLs
        } else {
            fileSelectionViewModel.leftURL = operation.sourceURL
            fileSelectionViewModel.rightURL = operation.destinationURLs.first
        }
        
        // Restore verification mode
        if let mode = VerificationMode.allCases.first(where: { $0.rawValue == operation.verificationMode }) {
            verificationMode = mode
        }
        
        // Restore progress
        progressViewModel.fileCountTotal = operation.totalCount
        progressViewModel.fileCountCompleted = operation.processedCount
        
        return (jobID: operation.id, jobStart: operation.startTime)
    }
}