import Foundation
import Testing
@testable import BitMatch

struct SFTPRemoteBackupProviderContractTests {
    @Test func firstUsePinsOnlyAnExplicitlyConfirmedFingerprint() async throws {
        var saved: [String: String] = [:]
        let store = SFTPHostFingerprintStore(
            save: { value, key in saved[key] = value; return true },
            load: { key in saved[key] }
        )

        try await store.validate(host: "backup.example", port: 22, fingerprint: "SHA256:first") { _ in true }

        #expect(saved[store.key(host: "backup.example", port: 22)] == "SHA256:first")
    }

    @Test func changedPinnedFingerprintBlocksBeforeAuthentication() async throws {
        let store = SFTPHostFingerprintStore(
            save: { _, _ in true },
            load: { _ in "SHA256:original" }
        )
        var askedForConfirmation = false

        await #expect(throws: RemoteBackupError.hostKeyMismatch) {
            try await store.validate(host: "backup.example", port: 22, fingerprint: "SHA256:changed") { _ in
                askedForConfirmation = true
                return true
            }
        }

        #expect(!askedForConfirmation)
    }

    @Test func rejectedFirstUseDoesNotPinFingerprint() async throws {
        var saveWasCalled = false
        let store = SFTPHostFingerprintStore(
            save: { _, _ in saveWasCalled = true; return true },
            load: { _ in nil }
        )

        await #expect(throws: RemoteBackupError.hostKeyMismatch) {
            try await store.validate(host: "backup.example", port: 22, fingerprint: "SHA256:first") { _ in false }
        }

        #expect(!saveWasCalled)
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
