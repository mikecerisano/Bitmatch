// CameraFolderNameTests.swift
import Foundation
import Testing
@testable import BitMatch

/// iPad and iPhone use the detected card's name as the default destination
/// folder label. These pin that name as it was before camera-detection-fixes
/// (ee976cb), so a card keeps going into the same folder ("GOPRO", not "GP").
struct CameraFolderNameTests {

    /// Every brand fixture, named by the brand its layout decides.
    /// Plant: in `SharedCameraDetectionService.cleanCameraName`, replace the
    /// body with `CleanCameraNameService.shared.getCleanCameraName(from: full)`
    /// (the ee976cb change: GoPro → "GP", Panasonic → "PANA", Blackmagic → "BMD").
    @Test func folderNameForEachBrandFixture() throws {
        let expected: [String: String] = [
            CameraCardLayouts.sonyVeniceAXS.name: "SONY",
            CameraCardLayouts.sonyVeniceSxS.name: "SONY",
            CameraCardLayouts.sonyXAVCPro.name: "SONY",
            CameraCardLayouts.sonyXDCAMEX.name: "SONY",
            CameraCardLayouts.sonyAlpha.name: "SONY",
            CameraCardLayouts.canonEOSStills.name: "CANON",
            CameraCardLayouts.canonEOSWithMP4.name: "CANON",
            CameraCardLayouts.canonXFAVC.name: "CANON",
            CameraCardLayouts.canonC70SD.name: "CANON",
            CameraCardLayouts.arriMiniLF.name: "ARRI",
            CameraCardLayouts.redR3D.name: "RED",
            CameraCardLayouts.blackmagicBRAW.name: "BLACKMAG",
            CameraCardLayouts.panasonicLumixStills.name: "PANASONI",
            CameraCardLayouts.panasonicP2.name: "PANASONI",
            CameraCardLayouts.fujifilmStills.name: "FUJIFILM",
            CameraCardLayouts.fujifilmWithMovie.name: "FUJIFILM",
            CameraCardLayouts.nikonStills.name: "NIKON",
            CameraCardLayouts.goPro.name: "GOPRO",
            CameraCardLayouts.djiLegacy.name: "DJI",
            CameraCardLayouts.djiCurrent.name: "DJI",
            CameraCardLayouts.insta360.name: "INSTA360",
        ]
        #expect(expected.count == CameraCardLayouts.all.count, "a fixture has no pinned folder name")

        for layout in CameraCardLayouts.all {
            let root = try layout.build()
            defer { try? FileManager.default.removeItem(at: root) }
            let brand = try #require(CardLayoutClassifier.classify(at: root)?.brand, "\(layout.name): no brand")
            let name = SharedCameraDetectionService.cameraCardName(manufacturer: brand, model: nil)
            #expect(name == expected[layout.name], "\(layout.name): folder name \(name)")
        }
    }

    /// When the card names a model, the folder is the model, cleaned as before.
    /// Plant: in `SharedCameraDetectionService.cameraCardName`, change
    /// `return cleanCameraName(model)` to
    /// `return cleanCameraName("\(manufacturer) \(model)")` ("SONYFX6").
    @Test func folderNameUsesTheModelWhenKnown() {
        let cases: [(String, String, String)] = [
            ("Sony", "FX6", "FX6"),         // Sony FX6 XAVC fixture's MEDIAPRO.XML
            ("Sony", "VENICE", "VENICE"),   // Sony VENICE SxS fixture
            ("Sony", "A7S III", "A7S3"),    // Sony Alpha fixture; the Mac label is A7SIII
            ("GoPro", "", "GOPRO"),         // an empty model falls back to the brand
        ]
        for (make, model, folder) in cases {
            #expect(SharedCameraDetectionService.cameraCardName(manufacturer: make, model: model) == folder,
                    "\(make) \(model)")
        }
    }
}
