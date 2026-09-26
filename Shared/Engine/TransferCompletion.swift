// TransferCompletion.swift - What a finished copy run means.
import Foundation

/// The engine's decisions once the pipeline returns: one result row per file
/// per backup, which backups get an ASC MHL history, and the verdict. The
/// app's `CopyVerifyExecutor` runs these and owns progress, timing and the
/// project lifecycle.
public enum TransferCompletion {
    // MARK: - Rows

    public static func row(from result: FileOperationResult, destinationRoots: [URL]) -> ResultRow {
        ResultRow(
            path: result.sourceURL.path,
            status: result.statusDescription,
            size: result.fileSize,
            checksum: result.verificationResult?.sourceChecksum,
            destination: destinationLabel(for: result.destinationURL, roots: destinationRoots),
            destinationPath: result.destinationURL.path
        )
    }

    public static func rows(from operation: FileOperation) -> [ResultRow] {
        operation.results.map { row(from: $0, destinationRoots: operation.destinationURLs) }
    }

    /// The backup a written file belongs to, as reports name it: the drive
    /// under /Volumes, otherwise the chosen backup folder. `/var` and
    /// `/private/var` spellings agree (see `ResultPathMatch`).
    public static func destinationLabel(for file: URL, roots: [URL]) -> String {
        let filePath = ResultPathMatch.comparablePath(file.path)
        let root = roots
            .map { URL(fileURLWithPath: ResultPathMatch.comparablePath($0.path)) }
            .filter { filePath == $0.path || filePath.hasPrefix($0.path + "/") }
            .max { $0.path.count < $1.path.count }
        let comps = (root ?? file).pathComponents
        if let volIndex = comps.firstIndex(of: "Volumes"), volIndex + 1 < comps.count {
            return comps[volIndex + 1]
        }
        return root?.lastPathComponent ?? file.deletingLastPathComponent().lastPathComponent
    }

    // MARK: - ASC MHL

    public struct ASCMHLJob: Sendable {
        public let root: URL
        public let files: [ASCMHLGenerator.VerifiedFile]
    }

    /// A history is written only for a backup whose every file verified
    /// with SHA-256; each other backup gets an issue saying why not.
    public static func ascmhlPlan(
        results: [FileOperationResult],
        destinations: [URL],
        source: URL,
        settings: CameraLabelSettings
    ) -> (jobs: [ASCMHLJob], issues: [String]) {
        let expectedPaths = Set(results.map { $0.sourceURL.standardizedFileURL.path })
        var jobs: [ASCMHLJob] = []
        var issues: [String] = []
        for destination in destinations {
            let root: URL
            do {
                root = try SafetyValidator.resolvedDestinationRootChecked(
                    source: source, destination: destination, settings: settings
                )
            } catch {
                issues.append("\(destination.lastPathComponent): ASC MHL not created — \(error.localizedDescription)")
                continue
            }
            let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
            let rows = results.filter { canonicalRoot.isAncestor(of: $0.destinationURL.standardizedFileURL.resolvingSymlinksInPath()) }
            guard !expectedPaths.isEmpty, rows.count == expectedPaths.count,
                  Set(rows.map { $0.sourceURL.standardizedFileURL.path }) == expectedPaths,
                  rows.allSatisfy({ $0.success && $0.verificationResult?.isValid == true && $0.verificationResult?.checksumType == .sha256 }) else {
                issues.append("\(destination.lastPathComponent): ASC MHL not created because verification is incomplete")
                continue
            }
            jobs.append(ASCMHLJob(root: root, files: rows.map {
                ASCMHLGenerator.VerifiedFile(
                    relativePath: $0.destinationURL.standardizedFileURL.resolvingSymlinksInPath().relativePath(to: canonicalRoot),
                    size: $0.fileSize, expectedSHA256: $0.verificationResult?.sourceChecksum ?? ""
                )
            }))
        }
        return (jobs, issues)
    }

    /// Writes each planned history and returns every issue: the plan's and
    /// any write failures. Blocking file I/O; run it off the main actor.
    public static func writeASCMHL(
        _ jobs: [ASCMHLJob],
        planIssues: [String],
        startTime: Date,
        source: URL,
        toolVersion: String
    ) throws -> [String] {
        var failures = planIssues
        for job in jobs {
            try Task.checkCancellation()
            do {
                _ = try ASCMHLGenerator.generateInitialHistory(
                    destinationURL: job.root, files: job.files, startTime: startTime,
                    sourceURL: source, toolVersion: toolVersion
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append("\(job.root.lastPathComponent): ASC MHL — \(error.localizedDescription)")
            }
        }
        return failures
    }

    // MARK: - Verdict

    /// What a project (photographer job) contributed to the outcome.
    public struct ProjectGate: Sendable {
        /// The project's records were saved.
        public let didPersist: Bool
        /// `nil` when no project finalizer ran (an ordinary copy).
        public let locallySafe: Bool?

        public var permitsSuccess: Bool { didPersist && (locallySafe ?? true) }
    }

    public struct Verdict: Equatable, Sendable {
        public let success: Bool
        public let message: String
    }

    /// Success needs every file on every backup to succeed, a checksum mode
    /// (never Quick), every requested ASC MHL written, the requested report
    /// saved, and the project (if any) saved and locally safe (Promise 2).
    public static func verdict(
        rows: [ResultRow],
        mode: VerificationMode,
        generateASCMHL: Bool,
        handoffIssues: [String],
        reportIssue: String?,
        project: ProjectGate
    ) -> Verdict {
        let issueCount = rows.filter { !$0.isSuccessStatus }.count
        let fileResultsSucceeded = !rows.isEmpty && issueCount == 0
        let fileResultsMessage = rows.isEmpty ? "No files were verified" : fileResultsSucceeded ?
            "Operation completed successfully" :
            "Operation completed with \(issueCount) issue\(issueCount == 1 ? "" : "s")"

        let succeeded = fileResultsSucceeded && project.permitsSuccess && handoffIssues.isEmpty && mode != .quick && reportIssue == nil
        var completionMessage: String
        if !project.didPersist {
            completionMessage = "\(fileResultsMessage); photographer lifecycle finalization failed"
        } else if project.locallySafe == false {
            completionMessage = "\(fileResultsMessage); photographer verification is incomplete"
        } else {
            completionMessage = fileResultsMessage
        }
        if !handoffIssues.isEmpty {
            completionMessage += "; " + handoffIssues.joined(separator: "; ")
        } else if generateASCMHL && mode != .quick {
            completionMessage += "; ASC MHL handoff records saved"
        }
        if mode == .quick {
            completionMessage += "; contents have not been checksum verified."
        }
        if let reportIssue {
            completionMessage += "; report export failed: \(reportIssue)"
        }
        return Verdict(success: succeeded, message: completionMessage)
    }
}
