// CameraCardLayoutDetectionTests.swift
import Foundation
import Testing
@testable import BitMatch

/// Camera detection against the card layouts in `CameraCardLayouts`.
///
/// Two kinds of test:
/// - Guards pin detection that is right today. Each names the one-line
///   production change that should make it fail.
/// - `withKnownIssue` tests record detection that is wrong today (see
///   docs/audits/2026-09-25-camera-detection.md). They are strict: when a
///   fix lands, the known issue stops reproducing, the test fails, and the
///   wrapper should be removed so the test becomes a guard.
///
/// Placeholder files are empty. Tests that run the full orchestrator avoid
/// MP4/MOV/JPG fixtures, because its first stage asks Spotlight (mdls)
/// about those files and that result depends on the machine.
struct CameraCardLayoutDetectionTests {

    private func withCard<T>(
        _ layout: CameraCardLayout,
        _ body: (URL) async throws -> T
    ) async throws -> T {
        let root = try layout.build()
        defer { try? FileManager.default.removeItem(at: root) }
        return try await body(root)
    }

    private func samePath(_ a: URL?, _ b: URL) -> Bool {
        a?.standardizedFileURL.path == b.standardizedFileURL.path
    }

    // MARK: - Fixture sanity

    @Test func everyLayoutBuildsItsDeclaredTree() async throws {
        for layout in CameraCardLayouts.all {
            #expect(!layout.source.isEmpty, "\(layout.name) has no source")
            try await withCard(layout) { root in
                for path in layout.directories + layout.files {
                    #expect(
                        FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                        "\(layout.name): missing \(path)"
                    )
                }
            }
        }
    }

    // MARK: - Mac auto-detect (CameraStructureDetector): guards

    /// Plant: delete `SonyCameraDetector(),` at CameraStructureDetector.swift:108
    /// (the card then falls through to CanonCameraDetector via 100MSDCF).
    @Test func structureDetectorFindsSonyAlpha() async throws {
        let card = try await withCard(CameraCardLayouts.sonyAlpha) {
            await CameraStructureDetector.detectCameraType(at: $0)
        }
        #expect(card?.cameraType == .sony)
    }

    /// Plant: delete `CanonCameraDetector(),` at CameraStructureDetector.swift:109
    /// (the card then lands on GenericDCIMDetector).
    @Test func structureDetectorFindsCanonStills() async throws {
        let card = try await withCard(CameraCardLayouts.canonEOSStills) {
            await CameraStructureDetector.detectCameraType(at: $0)
        }
        #expect(card?.cameraType == .canon)
    }

    /// Plant: delete `PanasonicDetector(),` at CameraStructureDetector.swift:110.
    @Test func structureDetectorFindsLumixStills() async throws {
        let card = try await withCard(CameraCardLayouts.panasonicLumixStills) {
            await CameraStructureDetector.detectCameraType(at: $0)
        }
        #expect(card?.cameraType == .panasonic)
    }

    /// Plant: delete `FujifilmDetector(),` at CameraStructureDetector.swift:111.
    @Test func structureDetectorFindsFujifilmStills() async throws {
        let card = try await withCard(CameraCardLayouts.fujifilmStills) {
            await CameraStructureDetector.detectCameraType(at: $0)
        }
        #expect(card?.cameraType == .fujifilm)
    }

    /// Plant: delete `Insta360Detector(),` at CameraStructureDetector.swift:115.
    @Test func structureDetectorFindsInsta360() async throws {
        let card = try await withCard(CameraCardLayouts.insta360) {
            await CameraStructureDetector.detectCameraType(at: $0)
        }
        #expect(card?.cameraType == .insta360)
    }

    // MARK: - Mac auto-detect (CameraStructureDetector): known issues

    /// Auto-select (Mac, opt-in) uses `mediaPath` as the transfer source.
    /// It must be the card root, or part of the card is silently left out.
    /// Today the Sony detector returns PRIVATE/, dropping DCIM stills.
    @Test func sonyAlphaMediaPathIsCardRoot() async throws {
        let layout = CameraCardLayouts.sonyAlpha
        let root = try layout.build()
        defer { try? FileManager.default.removeItem(at: root) }
        let card = await CameraStructureDetector.detectCameraType(at: root)
        await withKnownIssue("mediaPath is PRIVATE/, not the card root") {
            #expect(samePath(card?.mediaPath, root))
        }
    }

    /// Canon C70 on SD: the MP4 in DCIM matches the Sony detector, whose
    /// mediaPath then picks PRIVATE/ (slow-motion audio only).
    @Test func canonC70SDIsCanonWithRootMediaPath() async throws {
        let layout = CameraCardLayouts.canonC70SD
        let root = try layout.build()
        defer { try? FileManager.default.removeItem(at: root) }
        let card = await CameraStructureDetector.detectCameraType(at: root)
        await withKnownIssue("detected as Sony with mediaPath PRIVATE/") {
            #expect(card?.cameraType == .canon)
            #expect(samePath(card?.mediaPath, root))
        }
    }

    /// Layouts the Mac detector misses (nil) or labels as another brand.
    @Test func structureDetectorMisclassifiesOrMisses() async throws {
        let expectations: [(CameraCardLayout, CameraType)] = [
            (CameraCardLayouts.sonyVeniceAXS, .sony),       // nil
            (CameraCardLayouts.sonyVeniceSxS, .sony),       // nil: XDROOT not checked
            (CameraCardLayouts.sonyXAVCPro, .sony),         // nil: XDROOT not checked
            (CameraCardLayouts.sonyXDCAMEX, .sony),         // nil: BPAV not checked
            (CameraCardLayouts.canonEOSWithMP4, .canon),    // .sony: MP4 in DCIM
            (CameraCardLayouts.canonXFAVC, .canon),         // nil: no DCIM
            (CameraCardLayouts.arriMiniLF, .arri),          // nil: ARRI/ holds no media
            (CameraCardLayouts.redR3D, .redCamera),         // nil: root is *.RDM, not RED/
            (CameraCardLayouts.blackmagicBRAW, .blackmagic),// nil: clips at root, not BRAW/
            (CameraCardLayouts.panasonicP2, .panasonic),    // nil: no P2/ folder
            (CameraCardLayouts.fujifilmWithMovie, .fujifilm), // .canon: MOV in Canon list
            (CameraCardLayouts.nikonStills, .nikon),        // .canon: 100NIKON matches \d{3}[A-Z]+
            (CameraCardLayouts.goPro, .gopro),              // .sony: MP4 in DCIM
            (CameraCardLayouts.djiLegacy, .dji),            // .sony: MP4 in DCIM
            (CameraCardLayouts.djiCurrent, .dji),           // .sony: MP4 in DCIM
        ]
        for (layout, expected) in expectations {
            let root = try layout.build()
            defer { try? FileManager.default.removeItem(at: root) }
            let card = await CameraStructureDetector.detectCameraType(at: root)
            await withKnownIssue("\(layout.name) detected as \(card?.cameraType.rawValue ?? "nothing")") {
                #expect(card?.cameraType == expected, "\(layout.name)")
            }
        }
    }

    // MARK: - Orchestrator (labels, all platforms): guards

    /// Plant: in CameraDetectionOrchestrator.swift:36 change
    /// `{ return sonyInfo }` to `{ return "Canon" }`.
    @Test func orchestratorLabelsVeniceSxSAsSony() async throws {
        let result = try await withCard(CameraCardLayouts.sonyVeniceSxS) {
            CameraDetectionOrchestrator.shared.detectCamera(at: $0)
        }
        #expect(result?.hasPrefix("Sony") == true)
    }

    /// Plant: delete `"ILME-FX6": "FX6",` at SonyDetectionService.swift:136.
    @Test func orchestratorReadsFX6ModelFromMediaPro() async throws {
        let result = try await withCard(CameraCardLayouts.sonyXAVCPro) {
            CameraDetectionOrchestrator.shared.detectCamera(at: $0)
        }
        #expect(result == "Sony FX6")
    }

    /// Plant: in FolderStructureDetectionService.swift:53 change
    /// `"Canon", 1)` to `"Professional", 1)`.
    @Test func orchestratorLabelsXFAVCAsCanon() async throws {
        let result = try await withCard(CameraCardLayouts.canonXFAVC) {
            CameraDetectionOrchestrator.shared.detectCamera(at: $0)
        }
        #expect(result == "Canon")
    }

    /// Plant: in FolderStructureDetectionService.swift:58 change
    /// `"Panasonic", 2)` to `"Canon", 2)`.
    @Test func orchestratorLabelsP2AsPanasonic() async throws {
        let result = try await withCard(CameraCardLayouts.panasonicP2) {
            CameraDetectionOrchestrator.shared.detectCamera(at: $0)
        }
        #expect(result == "Panasonic")
    }

    /// Plant: in FileExtensionDetectionService.swift:44 change
    /// `("RED", 10)` to `("Professional", 10)`.
    @Test func orchestratorLabelsR3DAsRED() async throws {
        let result = try await withCard(CameraCardLayouts.redR3D) {
            CameraDetectionOrchestrator.shared.detectCamera(at: $0)
        }
        #expect(result == "RED")
    }

    /// Plant: in FileExtensionDetectionService.swift:45 change
    /// `("Blackmagic", 10)` to `("Professional", 10)`.
    @Test func orchestratorLabelsBRAWAsBlackmagic() async throws {
        let result = try await withCard(CameraCardLayouts.blackmagicBRAW) {
            CameraDetectionOrchestrator.shared.detectCamera(at: $0)
        }
        #expect(result == "Blackmagic")
    }

    /// Stage test: the orchestrator's first stage would see the MP4.
    /// Plant: in FolderStructureDetectionService.swift:47 change
    /// `"Sony", 1)` to `"Professional", 1)`.
    @Test func folderStructureLabelsXDCAMEXAsSony() async throws {
        let result = try await withCard(CameraCardLayouts.sonyXDCAMEX) {
            FolderStructureDetectionService.shared.detectCameraFromStructure(at: $0)
        }
        #expect(result == "Sony")
    }

    /// Stage test: ARRI support folder at the card root.
    /// Plant: in FolderStructureDetectionService.swift:82 change
    /// `"ARRI", 1)` to `"Professional", 1)`.
    @Test func folderStructureLabelsMiniLFAsARRI() async throws {
        let result = try await withCard(CameraCardLayouts.arriMiniLF) {
            FolderStructureDetectionService.shared.detectCameraFromStructure(at: $0)
        }
        #expect(result == "ARRI")
    }

    /// Stage test. Plant: in FujiDetectionService.swift:24 change
    /// `== "RAF"` to `== "RAW"`.
    @Test func fujiStageFindsRAF() async throws {
        let result = try await withCard(CameraCardLayouts.fujifilmStills) {
            FujiDetectionService.shared.detectFujiCamera(at: $0)
        }
        #expect(result == "Fujifilm")
    }

    // MARK: - Orchestrator: known issues

    /// GitHub #8 camera. X-OCN clips are MXF in a Cam ID + Reel folder; no
    /// stage recognises it, and the extension stage calls it "Professional".
    @Test func orchestratorLabelsVeniceAXSAsSony() async throws {
        let result = try await withCard(CameraCardLayouts.sonyVeniceAXS) {
            CameraDetectionOrchestrator.shared.detectCamera(at: $0)
        }
        await withKnownIssue("VENICE AXS card labelled \(result ?? "nil")") {
            #expect(result?.hasPrefix("Sony") == true)
        }
    }

    /// MPC-3610 (VENICE) is not in the systemKind table, so the label is
    /// plain "Sony".
    @Test func orchestratorNamesVenice() async throws {
        let result = try await withCard(CameraCardLayouts.sonyVeniceSxS) {
            CameraDetectionOrchestrator.shared.detectCamera(at: $0)
        }
        await withKnownIssue("VENICE model not mapped") {
            #expect(result?.uppercased().contains("VENICE") == true)
        }
    }

    /// Lumix stills (RW2 only, so no Spotlight stage): the Canon stage runs
    /// first and matches any card with DCIM plus MISC.
    @Test func orchestratorLabelsLumixAsPanasonic() async throws {
        let result = try await withCard(CameraCardLayouts.panasonicLumixStills) {
            CameraDetectionOrchestrator.shared.detectCamera(at: $0)
        }
        await withKnownIssue("Lumix labelled \(result ?? "nil")") {
            #expect(result == "Panasonic")
        }
    }

    /// DCIM + MISC hits the Canon pattern before the GoPro/DJI ones.
    @Test func folderStructureLabelsGoProAndDJI() async throws {
        let gopro = try await withCard(CameraCardLayouts.goPro) {
            FolderStructureDetectionService.shared.detectCameraFromStructure(at: $0)
        }
        await withKnownIssue("GoPro labelled \(gopro ?? "nil")") {
            #expect(gopro == "GoPro")
        }
        let dji = try await withCard(CameraCardLayouts.djiLegacy) {
            FolderStructureDetectionService.shared.detectCameraFromStructure(at: $0)
        }
        await withKnownIssue("DJI labelled \(dji ?? "nil")") {
            #expect(dji == "DJI")
        }
    }

    /// Full orchestrator on a GoPro card. On a Mac the first stage runs
    /// mdls on the MP4; with no Spotlight make/model it is expected to
    /// return "(null) (null)" (mdls prints "(null)" for missing
    /// attributes). Otherwise the Canon stage wins. Either way: not GoPro.
    @Test func orchestratorLabelsGoPro() async throws {
        let result = try await withCard(CameraCardLayouts.goPro) {
            CameraDetectionOrchestrator.shared.detectCamera(at: $0)
        }
        await withKnownIssue("GoPro labelled \(result ?? "nil")") {
            #expect(result == "GoPro")
        }
    }

    /// Mixed-case model string in an ALE ("ALEXA Mini LF") is read as
    /// "Alexa LF" because the MINI checks are case-sensitive.
    @Test func arriStageReadsMiniLFFromALE() async throws {
        let result = try await withCard(CameraCardLayouts.arriMiniLF) {
            ARRIDetectionService.shared.detectARRICamera(at: $0)
        }
        await withKnownIssue("ALE model read as \(result ?? "nil")") {
            #expect(result == "ARRI Alexa Mini LF")
        }
    }

    /// "ILCE-7SM3" also contains "ILCE-7S"; the lookup iterates a
    /// Dictionary, whose order changes per process, so the model flips
    /// between "A7S III" and "A7S". Intermittent by nature.
    @Test func sonyStageReadsA7SIII() async throws {
        let result = try await withCard(CameraCardLayouts.sonyAlpha) {
            SonyDetectionService.shared.detectSonyCamera(at: $0)
        }
        await withKnownIssue("systemKind lookup order is unstable", isIntermittent: true) {
            #expect(result == "Sony A7S III")
        }
    }
}
