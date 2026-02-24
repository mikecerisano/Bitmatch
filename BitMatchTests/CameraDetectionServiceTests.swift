import Foundation
import Testing
@testable import BitMatch

struct CameraDetectionServiceTests {

    @Test
    func testAnalyzeFolderStructureCapturesCountsAndExtensions() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let root = tmp.appendingPathComponent("bitmatch_camera_structure_\(UUID().uuidString)")
        let sub = root.appendingPathComponent("A001")
        try fm.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data("clip".utf8).write(to: sub.appendingPathComponent("C001.mov"), options: .atomic)
        try Data("<meta/>".utf8).write(to: root.appendingPathComponent("clip.xml"), options: .atomic)

        let sut = SharedCameraDetectionService()
        let structure = try await sut.analyzeFolderStructure(at: root)

        #expect((structure["total_files"] as? Int) == 2)
        #expect((structure["total_folders"] as? Int) == 1)
        let extensions = (structure["file_extensions"] as? [String]) ?? []
        #expect(extensions.contains("mov"))
        #expect(extensions.contains("xml"))

        try? fm.removeItem(at: root)
    }

    @Test
    func testParseXMLMetadataExtractsManufacturerAndModel() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let xmlURL = tmp.appendingPathComponent("bitmatch_camera_meta_\(UUID().uuidString).xml")
        let xml = """
        <metadata>
          <manufacturer>Canon</manufacturer>
          <model>C70</model>
          <camera>Main A</camera>
        </metadata>
        """
        try Data(xml.utf8).write(to: xmlURL, options: .atomic)

        let sut = SharedCameraDetectionService()
        let parsed = try await sut.parseXMLMetadata(from: xmlURL)

        #expect((parsed["manufacturer"] as? String) == "Canon")
        #expect((parsed["model"] as? String) == "C70")
        #expect((parsed["camera"] as? String) == "Main A")

        try? fm.removeItem(at: xmlURL)
    }

    @Test
    func testInferCameraTypeUsesManufacturerModelAndExtensions() {
        let redType = SharedCameraDetectionService.inferCameraType(
            manufacturer: "Unknown",
            model: nil,
            extensions: ["r3d"]
        )
        #expect(redType == .red)

        let arriType = SharedCameraDetectionService.inferCameraType(
            manufacturer: "ARRI",
            model: "Alexa Mini",
            extensions: ["mov"]
        )
        #expect(arriType == .arri)
    }
}
