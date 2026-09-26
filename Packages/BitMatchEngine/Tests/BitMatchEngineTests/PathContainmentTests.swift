// PathContainmentTests.swift
// One containment rule for the engine (plan C18). Paths are made up and
// never created, so every case is about the rule's text handling.
import Foundation
import Testing
@testable import BitMatchEngine

struct PathContainmentTests {
    private let base = "var/folders/bitmatch_contain_\(UUID().uuidString)"

    @Test func componentsNotPrefixes() {
        #expect(PathContainment.isWithin("/Volumes/T7/Card", root: "/Volumes/T7"))
        #expect(!PathContainment.isWithin("/Volumes/T70/Card", root: "/Volumes/T7"))
        #expect(PathContainment.isWithin("/Volumes/T7", root: "/Volumes/T7"))
        #expect(!PathContainment.isStrictlyWithin("/Volumes/T7", root: "/Volumes/T7"))
        #expect(PathContainment.isStrictlyWithin("/Volumes/T7/a", root: "/Volumes/T7/"))
    }

    /// Plant: make `comparableComponents` return the standardized components unchanged.
    @Test func privateAliasesMatchBothWays() {
        #expect(PathContainment.isWithin("/private/\(base)/CARD", root: "/\(base)"))
        #expect(PathContainment.isWithin("/\(base)/CARD", root: "/private/\(base)"))
        #expect(PathContainment.isSamePath("/private/\(base)", "/\(base)"))
        #expect(PathContainment.comparablePath("/private/\(base)/x") == "/\(base)/x")
        #expect(!PathContainment.isWithin("/privatevar/x", root: "/var"))
    }

    /// A restored backup in the temporary folder is refused under either
    /// spelling. (Symlink resolution already made both spellings agree here
    /// before C18; this pins it.)
    /// Plant: delete the temporary-roots check in `BackupTargetPolicy.refusal`.
    @Test func backupPolicyRefusesTemporaryFolderAcrossAlias() {
        let temporary = URL(fileURLWithPath: "/private/\(base)/T", isDirectory: true)
        let target = URL(fileURLWithPath: "/\(base)/T/Backups", isDirectory: true)
        let facts = BackupTargetPolicy.VolumeFacts(
            volumeRootPath: "/Volumes/Scratch", volumeID: "SCRATCH", volumeName: "Scratch",
            isRootFileSystem: false, isInternal: false, isRemovable: true, isEjectable: true
        )
        let refusal = BackupTargetPolicy.refusal(
            for: target, origin: .restored, source: nil,
            facts: { _ in facts }, temporaryDirectory: temporary
        )
        #expect(refusal?.hasSuffix("is a temporary folder.") == true)
    }

    /// The same backup chosen under both spellings is a duplicate.
    /// Plant: in `TransferReadiness.assess`, drop `PathContainment.comparablePath` from the uniqueness set.
    @Test func sameBackupUnderBothSpellingsIsADuplicate() {
        let readiness = TransferReadiness.assess(
            source: URL(fileURLWithPath: "/Volumes/CARD", isDirectory: true), sourceBytes: 1,
            isAnalysingSource: false,
            destinations: [URL(fileURLWithPath: "/private/\(base)/SSD"), URL(fileURLWithPath: "/\(base)/SSD")],
            settings: CameraLabelSettings(), verificationMode: .standard,
            availableBytes: { _ in .max }, isWritable: { _ in true }
        )
        #expect(readiness.blockers.contains("Destination folders must be unique"))
    }
}
