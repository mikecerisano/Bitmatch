import Testing
@testable import BitMatchEngine

struct CameraLabelSettingsTests {

    @Test
    func testFormattedFolderNameUsesBaseNameWhenLabelIsEmpty() {
        let settings = CameraLabelSettings()
        let folderName = settings.formattedFolderName(for: "A001_C001")
        #expect(folderName == "A001_C001")
    }
}
