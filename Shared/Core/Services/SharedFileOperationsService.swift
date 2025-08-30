// SharedFileOperationsService.swift - Platform-agnostic file operations
import Foundation

class SharedFileOperationsService: FileOperationsService {
    typealias ProgressCallback = (OperationProgress) -> Void
    
    private let fileSystem: FileSystemService
    private let checksumService: any ChecksumService
    private var currentOperation: Task<FileOperation, Error>?
    private var isPaused = false
    
    init(fileSystem: FileSystemService, checksum: any ChecksumService) {
        self.fileSystem = fileSystem
        self.checksumService = checksum
    }
    
    // MARK: - FileOperationsService Protocol Implementation
    
    func performFileOperation(
        sourceURL: URL,
        destinationURLs: [URL],
        verificationMode: VerificationMode,
        settings: CameraLabelSettings,
        progressCallback: @escaping ProgressCallback
    ) async throws -> FileOperation {
        
        // Cancel any existing operation
        cancelOperation()
        
        let operation = FileOperation(
            sourceURL: sourceURL,
            destinationURLs: destinationURLs,
            startTime: Date(),
            endTime: nil,
            results: [],
            verificationMode: verificationMode,
            settings: settings
        )
        
        currentOperation = Task {
            return try await executeOperation(operation, progressCallback: progressCallback)
        }
        
        return try await currentOperation!.value
    }
    
    func cancelOperation() {
        currentOperation?.cancel()
        currentOperation = nil
    }
    
    func pauseOperation() async {
        isPaused = true
    }
    
    func resumeOperation() async {
        isPaused = false
    }
    
    // MARK: - Private Implementation
    
    private func executeOperation(
        _ operation: FileOperation,
        progressCallback: @escaping ProgressCallback
    ) async throws -> FileOperation {
        
        var results: [FileOperationResult] = []
        
        // Step 1: Validate access to all URLs
        progressCallback(OperationProgress(
            overallProgress: 0.0,
            currentFile: nil,
            filesProcessed: 0,
            totalFiles: 0,
            currentStage: .preparing,
            speed: nil,
            timeRemaining: nil
        ))
        
        guard await fileSystem.validateFileAccess(url: operation.sourceURL) else {
            throw BitMatchError.fileAccessDenied(operation.sourceURL)
        }
        
        for destinationURL in operation.destinationURLs {
            guard await fileSystem.validateFileAccess(url: destinationURL) else {
                throw BitMatchError.fileAccessDenied(destinationURL)
            }
        }
        
        // Step 2: Get file list
        let fileURLs = try await fileSystem.getFileList(from: operation.sourceURL)
        let totalFiles = fileURLs.count * operation.destinationURLs.count
        var processedFiles = 0
        
        // Step 3: Copy files to each destination
        let startTime = Date()
        var totalBytesProcessed: Int64 = 0
        
        for (_, destinationURL) in operation.destinationURLs.enumerated() {
            let destFolder = destinationURL.appendingPathComponent(operation.sourceURL.lastPathComponent)
            try fileSystem.createDirectory(at: destFolder)
            
            for (_, fileURL) in fileURLs.enumerated() {
                // Check for cancellation
                try Task.checkCancellation()
                
                // Handle pause
                while isPaused && !Task.isCancelled {
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
                
                let destinationFileURL = destFolder.appendingPathComponent(fileURL.lastPathComponent)
                let fileStartTime = Date()
                
                do {
                    // Update progress
                    let overallProgress = Double(processedFiles) / Double(totalFiles)
                    let currentFileName = fileURL.lastPathComponent
                    
                    // Calculate speed and time remaining
                    let elapsedTime = Date().timeIntervalSince(startTime)
                    let speed = elapsedTime > 0 ? Double(totalBytesProcessed) / elapsedTime : nil
                    let timeRemaining = speed != nil && speed! > 0 ? 
                        Double(totalFiles - processedFiles) * (elapsedTime / Double(processedFiles + 1)) : nil
                    
                    progressCallback(OperationProgress(
                        overallProgress: overallProgress,
                        currentFile: currentFileName,
                        filesProcessed: processedFiles,
                        totalFiles: totalFiles,
                        currentStage: .copying,
                        speed: speed,
                        timeRemaining: timeRemaining
                    ))
                    
                    // Copy the file
                    try await fileSystem.copyFile(from: fileURL, to: destinationFileURL)
                    let fileSize = try fileSystem.getFileSize(for: fileURL)
                    totalBytesProcessed += fileSize
                    
                    // Verify if requested
                    var verificationResult: VerificationResult? = nil
                    if operation.verificationMode != .standard || operation.verificationMode == .paranoid {
                        progressCallback(OperationProgress(
                            overallProgress: overallProgress,
                            currentFile: currentFileName,
                            filesProcessed: processedFiles,
                            totalFiles: totalFiles,
                            currentStage: .verifying,
                            speed: speed,
                            timeRemaining: timeRemaining
                        ))
                        
                        // Use appropriate verification method
                        if operation.verificationMode == .paranoid {
                            let matches = try await checksumService.performByteComparison(
                                sourceURL: fileURL,
                                destinationURL: destinationFileURL,
                                progressCallback: nil as ChecksumService.ProgressCallback?
                            )
                            verificationResult = VerificationResult(
                                sourceChecksum: "byte-comparison",
                                destinationChecksum: "byte-comparison",
                                matches: matches,
                                checksumType: .sha256,
                                processingTime: Date().timeIntervalSince(fileStartTime),
                                fileSize: fileSize
                            )
                        } else {
                            // Use checksum verification
                            let checksumType = operation.verificationMode.checksumTypes.first ?? .sha256
                            verificationResult = try await checksumService.verifyFileIntegrity(
                                sourceURL: fileURL,
                                destinationURL: destinationFileURL,
                                type: checksumType,
                                progressCallback: nil
                            )
                        }
                    }
                    
                    let result = FileOperationResult(
                        sourceURL: fileURL,
                        destinationURL: destinationFileURL,
                        success: true,
                        error: nil,
                        fileSize: fileSize,
                        verificationResult: verificationResult,
                        processingTime: Date().timeIntervalSince(fileStartTime)
                    )
                    
                    results.append(result)
                    
                } catch {
                    let result = FileOperationResult(
                        sourceURL: fileURL,
                        destinationURL: destinationFileURL,
                        success: false,
                        error: error,
                        fileSize: 0,
                        verificationResult: nil,
                        processingTime: Date().timeIntervalSince(fileStartTime)
                    )
                    
                    results.append(result)
                }
                
                processedFiles += 1
            }
        }
        
        // Final progress update
        progressCallback(OperationProgress(
            overallProgress: 1.0,
            currentFile: nil,
            filesProcessed: totalFiles,
            totalFiles: totalFiles,
            currentStage: .completed,
            speed: nil,
            timeRemaining: 0
        ))
        
        return FileOperation(
            sourceURL: operation.sourceURL,
            destinationURLs: operation.destinationURLs,
            startTime: operation.startTime,
            endTime: Date(),
            results: results,
            verificationMode: operation.verificationMode,
            settings: operation.settings
        )
    }
}