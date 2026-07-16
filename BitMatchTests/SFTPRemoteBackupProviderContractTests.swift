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

    @Test func existingFinalFromLnIsClassifiedAsConflict() {
        #if os(macOS)
        #expect(SFTPRemoteBackupProvider.promotionError(stderr: Data("ln: File exists".utf8)) == .conflict)
        #expect(SFTPRemoteBackupProvider.promotionError(stderr: Data("shell disabled".utf8)) == .capabilityUnavailable(.noReplacePromotion))
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
