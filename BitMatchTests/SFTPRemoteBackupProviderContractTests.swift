import Foundation
import Testing
@testable import BitMatch

struct SFTPRemoteBackupProviderContractTests {
    @Test func opensshUsesStrictNoninteractiveAgentOnlyArguments() {
        #if os(macOS)
        let arguments = SFTPRemoteBackupProvider.fixedArguments(
            knownHostsURL: URL(fileURLWithPath: "/tmp/profile/known_hosts"), port: 2222, username: "archive", portFlag: "-p"
        )
        #expect(arguments.contains("BatchMode=yes"))
        #expect(arguments.contains("StrictHostKeyChecking=yes"))
        #expect(arguments.contains("PasswordAuthentication=no"))
        #expect(arguments.contains("KbdInteractiveAuthentication=no"))
        #expect(arguments.contains("PreferredAuthentications=publickey"))
        #expect(arguments.contains("UserKnownHostsFile=/tmp/profile/known_hosts"))

        let sftpArguments = SFTPRemoteBackupProvider.fixedArguments(
            knownHostsURL: URL(fileURLWithPath: "/tmp/profile/known_hosts"), port: 2222, username: nil, portFlag: "-P"
        )
        #expect(!sftpArguments.contains("-l"))
        #endif
    }

    @Test func remotePathsUsePOSIXSingleQuoteEscaping() {
        #if os(macOS)
        #expect(SFTPRemoteBackupProvider.shellQuote("/remote/O'Reilly.mov") == "'/remote/O'\\\"'\\\"'Reilly.mov'")
        #endif
    }

    @Test func sftpArgumentsEscapeQuotesAndRejectControlCharacters() throws {
        #if os(macOS)
        #expect(try SFTPRemoteBackupProvider.sftpQuote("/tmp/a\\b\"c") == "\"/tmp/a\\\\b\\\"c\"")
        #expect(throws: RemoteBackupError.unsafePath) {
            try SFTPRemoteBackupProvider.sftpQuote("/tmp/injected\nput target")
        }
        #endif
    }

    @Test func remotePathsRemainRelativeToTheSFTPAccountRoot() throws {
        #if os(macOS)
        let root = try RemoteRelativePath(components: ["Backups"])
        let file = try RemoteRelativePath(components: ["Jobs", "Card-001.mov"])
        #expect(try SFTPRemoteBackupProvider.relativeRemotePath(root: root, path: file) == "Backups/Jobs/Card-001.mov")
        #endif
    }

    @Test func existingFinalFromLnIsClassifiedAsConflict() {
        #if os(macOS)
        #expect(SFTPRemoteBackupProvider.promotionError(stderr: Data("ln: File exists".utf8)) == .conflict)
        #expect(SFTPRemoteBackupProvider.promotionError(stderr: Data("shell disabled".utf8)) == .capabilityUnavailable(.noReplacePromotion))
        #endif
    }

    @Test func hostKeyVerificationFailureIsClassifiedBeforeCapabilityFailure() {
        #if os(macOS)
        #expect(SFTPRemoteBackupProvider.classify(stderr: Data("Host key verification failed.".utf8)) == .hostKeyMismatch)
        #endif
    }

    @Test func firstTrustScansAndFingerprintsBeforeSSHAuthentication() async throws {
        #if os(macOS)
        let recorder = OpenSSHCommandRecorder()
        let knownHosts = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("known_hosts")
        defer { try? FileManager.default.removeItem(at: knownHosts.deletingLastPathComponent()) }
        let provider = SFTPRemoteBackupProvider(
            profile: try fixtureProfile(), credential: .sshAgent, knownHostsURL: knownHosts,
            confirmUnknownHost: { request in request.sha256Fingerprint.contains("SHA256:test") },
            run: { command in await recorder.run(command) }
        )

        _ = try await provider.preflight(profile: try fixtureProfile(), credential: .sshAgent)

        let commands = await recorder.commands()
        #expect(commands.map(\.executable) == ["/usr/bin/ssh-keyscan", "/usr/bin/ssh-keygen", "/usr/bin/ssh"])
        #endif
    }

    @Test func resumeOffsetMismatchStopsBeforeSFTPTransfer() async throws {
        #if os(macOS)
        let recorder = OpenSSHCommandRecorder(inspectLength: 3)
        let knownHosts = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("known_hosts")
        try FileManager.default.createDirectory(at: knownHosts.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("backup.example ssh-ed25519 AAAA\n".utf8).write(to: knownHosts)
        defer { try? FileManager.default.removeItem(at: knownHosts.deletingLastPathComponent()) }
        let provider = SFTPRemoteBackupProvider(profile: try fixtureProfile(), credential: .sshAgent, knownHostsURL: knownHosts, run: { command in await recorder.run(command) })
        let temporary = try RemoteRelativePath(components: ["Jobs", ".bitmatch-upload-item"])

        await #expect(throws: RemoteBackupError.resumeOffsetMismatch(local: 2, remote: 3)) {
            try await provider.upload(local: URL(fileURLWithPath: "/tmp/local.mov"), toTemporary: temporary, fromOffset: 2) { _ in }
        }

        #expect(!(await recorder.commands()).contains(where: { $0.executable == "/usr/bin/sftp" }))
        #endif
    }

    @Test func verifiedModeRequiresNoReplacePromotionCapability() async throws {
        let capabilities = RemoteProviderCapabilities(
            supportsNoReplacePromotion: false,
            supportsVerificationEvidence: true
        )

        #expect(capabilities.missingRequirements(for: .sha256) == [.noReplacePromotion])
    }

    @Test func verifiedModeRequiresVerificationEvidenceCapability() async throws {
        let capabilities = RemoteProviderCapabilities(
            supportsNoReplacePromotion: true,
            supportsVerificationEvidence: false
        )

        #expect(capabilities.missingRequirements(for: .sha256) == [.verificationEvidence])
    }

    @Test func uploadOnlyStillRequiresNoReplacePromotion() async throws {
        let capabilities = RemoteProviderCapabilities(
            supportsNoReplacePromotion: false,
            supportsVerificationEvidence: false
        )

        #expect(capabilities.missingRequirements(for: .uploadOnly) == [.noReplacePromotion])
    }

    @Test func typedRemoteErrorsClassifyRetryabilityAndFailClosedState() {
        #expect(RemoteBackupError.networkUnavailable.isTransientNetworkFault)
        #expect(!RemoteBackupError.authenticationFailed.isTransientNetworkFault)
        #expect(RemoteBackupError.authenticationFailed.failClosedState == .paused)
        #expect(RemoteBackupError.unsafePath.failClosedState == .paused)
        #expect(RemoteBackupError.permissionDenied.failClosedState == .paused)
    }
}

#if os(macOS)
private func fixtureProfile() throws -> RemoteDestinationProfile {
    RemoteDestinationProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Archive",
        host: "backup.example", port: 22, username: "archive",
        root: try RemoteRelativePath(components: ["Backups"]), verificationMode: .sha256
    )
}

private actor OpenSSHCommandRecorder {
    private var recorded: [OpenSSHCommand] = []
    private let inspectLength: Int64?

    init(inspectLength: Int64? = nil) { self.inspectLength = inspectLength }

    func run(_ command: OpenSSHCommand) -> OpenSSHCommandResult {
        recorded.append(command)
        switch command.executable {
        case "/usr/bin/ssh-keyscan":
            return .init(status: 0, stdout: Data("backup.example ssh-ed25519 AAAA\n".utf8), stderr: Data())
        case "/usr/bin/ssh-keygen":
            return .init(status: 0, stdout: Data("256 SHA256:test backup.example\n".utf8), stderr: Data())
        case "/usr/bin/ssh":
            let output = inspectLength.map { Data("\($0)\n".utf8) } ?? Data()
            return .init(status: 0, stdout: output, stderr: Data())
        default:
            return .init(status: 1, stdout: Data(), stderr: Data("unexpected command".utf8))
        }
    }

    func commands() -> [OpenSSHCommand] { recorded }
}
#endif
