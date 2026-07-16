import Foundation

enum SFTPRemoteBackupProviderFactory {
    static func make(profile: RemoteDestinationProfile, credential: RemoteCredential) async throws -> any RemoteBackupProvider {
        #if os(macOS)
        return SFTPRemoteBackupProvider(profile: profile, credential: credential)
        #else
        throw RemoteBackupError.providerUnavailable
        #endif
    }
}

#if os(macOS)
struct OpenSSHCommand: Equatable, Sendable {
    let executable: String
    let arguments: [String]
    let standardInput: Data?
}

struct OpenSSHCommandResult: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: Data
}

struct OpenSSHHostTrustRequest: Equatable, Sendable {
    let host: String
    let port: Int
    let sha256Fingerprint: String
}

/// The confirmation closure is an intentional UI boundary. It must display
/// the supplied fingerprint and return true only after deliberate user
/// confirmation; the adapter persists the exact scanned key material itself.
typealias OpenSSHHostTrustConfirmation = @Sendable (OpenSSHHostTrustRequest) async throws -> Bool
typealias OpenSSHCommandRunner = @Sendable (OpenSSHCommand) async throws -> OpenSSHCommandResult

actor SFTPRemoteBackupProvider: RemoteBackupProvider {
    private let profile: RemoteDestinationProfile
    private let credential: RemoteCredential
    private let knownHostsURL: URL
    private let confirmUnknownHost: OpenSSHHostTrustConfirmation?
    private let run: OpenSSHCommandRunner

    init(
        profile: RemoteDestinationProfile,
        credential: RemoteCredential,
        knownHostsURL: URL? = nil,
        confirmUnknownHost: OpenSSHHostTrustConfirmation? = nil,
        run: OpenSSHCommandRunner? = nil
    ) {
        self.profile = profile
        self.credential = credential
        self.knownHostsURL = knownHostsURL ?? Self.profileKnownHostsURL(profileID: profile.id)
        self.confirmUnknownHost = confirmUnknownHost
        self.run = run ?? SFTPRemoteBackupProvider.runProcess
    }

    func preflight(profile requested: RemoteDestinationProfile, credential supplied: RemoteCredential) async throws -> RemoteProviderCapabilities {
        guard requested.id == profile.id, supplied == credential, supplied.isSSHAgentOnly else {
            throw RemoteBackupError.authenticationFailed
        }
        try await establishExplicitTrustIfNeeded()
        let result = try await run(ssh(command: "command -v ln >/dev/null 2>&1 && command -v rm >/dev/null 2>&1"))
        guard result.status == 0 else { throw RemoteBackupError.capabilityUnavailable(.noReplacePromotion) }
        return RemoteProviderCapabilities(supportsNoReplacePromotion: true, supportsVerificationEvidence: true)
    }

    func inspect(path: RemoteRelativePath) async throws -> RemoteObject? {
        let result = try await run(ssh(command: "if test -e \(shellQuote(remote(path))); then wc -c < \(shellQuote(remote(path))); fi"))
        guard result.status == 0 else { throw classify(result) }
        let output = String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return nil }
        guard let count = Int64(output), count >= 0 else { throw RemoteBackupError.providerUnavailable }
        return RemoteObject(byteCount: count)
    }

    func ensureDirectory(_ path: RemoteRelativePath) async throws {
        let result = try await run(ssh(command: "mkdir -p \(shellQuote(remote(path)))"))
        guard result.status == 0 else { throw classify(result) }
    }

    func upload(local: URL, toTemporary path: RemoteRelativePath, fromOffset: Int64, progress: @Sendable (Int64) async -> Void) async throws {
        guard fromOffset >= 0 else { throw RemoteBackupError.resumeOffsetMismatch(local: fromOffset, remote: 0) }
        let remoteObject = try await inspect(path: path)
        guard (remoteObject?.byteCount ?? 0) == fromOffset else {
            throw RemoteBackupError.resumeOffsetMismatch(local: fromOffset, remote: remoteObject?.byteCount ?? 0)
        }
        let batch = "put -a \(sftpQuote(local.path)) \(sftpQuote(remote(path)))\n"
        let result = try await run(sftp(batch: batch))
        guard result.status == 0 else { throw classify(result) }
        let complete = try await inspect(path: path)?.byteCount ?? 0
        await progress(complete)
    }

    func promoteNoReplace(temporary: RemoteRelativePath, final: RemoteRelativePath) async throws {
        let command = "ln \(shellQuote(remote(temporary))) \(shellQuote(remote(final))) && rm \(shellQuote(remote(temporary)))"
        let result = try await run(ssh(command: command))
        guard result.status == 0 else { throw classifyPromotion(result) }
    }

    func verificationEvidence(for path: RemoteRelativePath, expectedSHA256: String) async throws -> RemoteVerificationEvidence {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let result = try await run(sftp(batch: "get \(sftpQuote(remote(path))) \(sftpQuote(temporary.path))\n"))
        guard result.status == 0 else { throw classify(result) }
        let actual = try await SharedChecksumService.shared.generateChecksum(for: temporary, type: .sha256, useCache: false)
        guard actual.caseInsensitiveCompare(expectedSHA256) == .orderedSame else { throw RemoteBackupError.verificationFailed }
        return .readBackSHA256(actual)
    }

    func close() async {}

    static func profileKnownHostsURL(profileID: UUID) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("BitMatch/SFTP/\(profileID.uuidString.lowercased())/known_hosts")
    }

    private func establishExplicitTrustIfNeeded() async throws {
        guard !FileManager.default.fileExists(atPath: knownHostsURL.path) else { return }
        guard let confirmUnknownHost else { throw RemoteBackupError.hostKeyMismatch }
        let scanned = try await run(OpenSSHCommand(
            executable: "/usr/bin/ssh-keyscan",
            arguments: ["-p", "\(profile.port)", profile.host],
            standardInput: nil
        ))
        guard scanned.status == 0, !scanned.stdout.isEmpty else { throw RemoteBackupError.hostKeyMismatch }
        let fingerprint = try await run(OpenSSHCommand(
            executable: "/usr/bin/ssh-keygen",
            arguments: ["-lf", "-", "-E", "sha256"],
            standardInput: scanned.stdout
        ))
        guard fingerprint.status == 0, !fingerprint.stdout.isEmpty else { throw RemoteBackupError.hostKeyMismatch }
        let request = OpenSSHHostTrustRequest(
            host: profile.host,
            port: profile.port,
            sha256Fingerprint: String(decoding: fingerprint.stdout, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard try await confirmUnknownHost(request) else { throw RemoteBackupError.hostKeyMismatch }
        try FileManager.default.createDirectory(at: knownHostsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try scanned.stdout.write(to: knownHostsURL, options: .atomic)
    }

    private func ssh(command: String) -> OpenSSHCommand {
        OpenSSHCommand(executable: "/usr/bin/ssh", arguments: commonArguments(portFlag: "-p") + ["-T", profile.host, command], standardInput: nil)
    }

    private func sftp(batch: String) -> OpenSSHCommand {
        OpenSSHCommand(executable: "/usr/bin/sftp", arguments: sftpArguments() + ["-b", "-", "\(profile.username)@\(profile.host)"], standardInput: Data(batch.utf8))
    }

    private func commonArguments(portFlag: String) -> [String] {
        Self.fixedArguments(knownHostsURL: knownHostsURL, port: profile.port, username: profile.username, portFlag: portFlag)
    }

    private func sftpArguments() -> [String] {
        Self.fixedArguments(knownHostsURL: knownHostsURL, port: profile.port, username: nil, portFlag: "-P")
    }

    private func remote(_ path: RemoteRelativePath) -> String { "/\(profile.root.description)/\(path.description)" }
    private func shellQuote(_ value: String) -> String { Self.shellQuote(value) }
    private func sftpQuote(_ value: String) -> String { "\"\(value.replacingOccurrences(of: "\\\"", with: "\\\\\\\""))\"" }

    private func classify(_ result: OpenSSHCommandResult) -> RemoteBackupError {
        let text = String(decoding: result.stderr, as: UTF8.self).lowercased()
        if text.contains("host key verification") || text.contains("no matching host key") { return .hostKeyMismatch }
        if text.contains("permission denied") { return .permissionDenied }
        if text.contains("authentication") { return .authenticationFailed }
        return .networkUnavailable
    }

    private func classifyPromotion(_ result: OpenSSHCommandResult) -> RemoteBackupError {
        Self.promotionError(stderr: result.stderr)
    }

    static func fixedArguments(knownHostsURL: URL, port: Int, username: String?, portFlag: String) -> [String] {
        var arguments = ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "UserKnownHostsFile=\(knownHostsURL.path)", "-o", "GlobalKnownHostsFile=/dev/null", "-o", "PasswordAuthentication=no", "-o", "KbdInteractiveAuthentication=no", "-o", "PreferredAuthentications=publickey", "-o", "PubkeyAuthentication=yes", portFlag, "\(port)"]
        if let username { arguments += ["-l", username] }
        return arguments
    }

    static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\\"'\\\"'"))'"
    }

    static func promotionError(stderr: Data) -> RemoteBackupError {
        String(decoding: stderr, as: UTF8.self).lowercased().contains("file exists")
            ? .conflict
            : .capabilityUnavailable(.noReplacePromotion)
    }

    private static func runProcess(_ command: OpenSSHCommand) async throws -> OpenSSHCommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe(); let error = Pipe(); let input = Pipe()
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
            process.standardOutput = output; process.standardError = error; process.standardInput = input
            process.terminationHandler = { completed in
                continuation.resume(returning: OpenSSHCommandResult(status: completed.terminationStatus, stdout: output.fileHandleForReading.readDataToEndOfFile(), stderr: error.fileHandleForReading.readDataToEndOfFile()))
            }
            do {
                try process.run()
                if let data = command.standardInput { input.fileHandleForWriting.write(data) }
                input.fileHandleForWriting.closeFile()
            } catch { continuation.resume(throwing: error) }
        }
    }
}
#endif
