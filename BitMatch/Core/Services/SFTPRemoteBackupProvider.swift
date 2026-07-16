import Foundation

/// The only factory used by the shared queue.  iPad deliberately has no SFTP
/// implementation or Citadel linkage.
enum SFTPRemoteBackupProviderFactory {
    static func make(
        profile: RemoteDestinationProfile,
        credential: RemoteCredential
    ) async throws -> any RemoteBackupProvider {
        #if os(macOS)
        return SFTPRemoteBackupProvider(profile: profile, credential: credential)
        #else
        throw RemoteBackupError.providerUnavailable
        #endif
    }
}

#if os(macOS)
import Citadel

/// Citadel 0.12.x is intentionally fail-closed.  Its public API does not
/// expose stable host-key bytes for SHA-256 fingerprinting and only provides a
/// potentially replacing SFTP rename.  Connecting would require accepting a
/// key before it can be fingerprinted, and promotion could overwrite a final.
/// Therefore no credential is sent and no SFTP session is opened until Citadel
/// provides both capabilities.
actor SFTPRemoteBackupProvider: RemoteBackupProvider {
    private let profile: RemoteDestinationProfile
    private let credential: RemoteCredential

    init(profile: RemoteDestinationProfile, credential: RemoteCredential) {
        self.profile = profile
        self.credential = credential
    }

    func preflight(
        profile requestedProfile: RemoteDestinationProfile,
        credential requestedCredential: RemoteCredential
    ) async throws -> RemoteProviderCapabilities {
        // Keep the values referenced so future capability support cannot
        // accidentally authenticate a profile other than the factory input.
        guard requestedProfile.id == profile.id, requestedCredential == credential else {
            throw RemoteBackupError.authenticationFailed
        }
        throw RemoteBackupError.capabilityUnavailable(.noReplacePromotion)
    }

    func inspect(path _: RemoteRelativePath) async throws -> RemoteObject? {
        throw RemoteBackupError.providerUnavailable
    }

    func ensureDirectory(_: RemoteRelativePath) async throws {
        throw RemoteBackupError.providerUnavailable
    }

    func upload(
        local _: URL,
        toTemporary _: RemoteRelativePath,
        fromOffset _: Int64,
        progress _: @Sendable (Int64) async -> Void
    ) async throws {
        throw RemoteBackupError.providerUnavailable
    }

    func promoteNoReplace(temporary _: RemoteRelativePath, final _: RemoteRelativePath) async throws {
        throw RemoteBackupError.capabilityUnavailable(.noReplacePromotion)
    }

    func verificationEvidence(
        for _: RemoteRelativePath,
        expectedSHA256 _: String
    ) async throws -> RemoteVerificationEvidence {
        throw RemoteBackupError.capabilityUnavailable(.verificationEvidence)
    }

    func close() async {}
}
#endif
