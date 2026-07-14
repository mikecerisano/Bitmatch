import Foundation
import Testing
@testable import BitMatch

struct PhotographerCardAnalyzerTests {
    @Test func preliminaryFingerprintIgnoresEnumerationOrder() throws {
        let date = Date(timeIntervalSince1970: 100)
        let a = FileEntry(url: URL(fileURLWithPath: "/card/DCIM/A.ARW"), relativePath: "DCIM/A.ARW", size: 10, modificationDate: date)
        let b = FileEntry(url: URL(fileURLWithPath: "/card/DCIM/A.JPG"), relativePath: "DCIM/A.JPG", size: 5, modificationDate: date)
        #expect(try PhotographerCardAnalyzer.preliminaryAnalysis(entries: [a, b]).fingerprint ==
                PhotographerCardAnalyzer.preliminaryAnalysis(entries: [b, a]).fingerprint)
    }

    @Test func rawAndJpegWithSameStemFormOneGroup() throws {
        let entries = [
            FileEntry(url: URL(fileURLWithPath: "/c/A.ARW"), relativePath: "A.ARW", size: 10, modificationDate: nil),
            FileEntry(url: URL(fileURLWithPath: "/c/A.JPG"), relativePath: "A.JPG", size: 5, modificationDate: nil),
            FileEntry(url: URL(fileURLWithPath: "/c/A.XMP"), relativePath: "A.XMP", size: 1, modificationDate: nil)
        ]
        let analysis = try PhotographerCardAnalyzer.preliminaryAnalysis(entries: entries)
        let group = try #require(analysis.companionGroups.first)
        #expect(analysis.companionGroups.count == 1)
        #expect(group.rawPaths == ["A.ARW"])
        #expect(group.jpegPaths == ["A.JPG"])
        #expect(group.sidecarPaths == ["A.XMP"])
    }

    @Test func canonicalPathCollisionStillIgnoresEnumerationOrder() throws {
        let earlier = FileEntry(
            url: URL(fileURLWithPath: "/card/A.JPG"),
            relativePath: "A.JPG",
            size: 5,
            modificationDate: Date(timeIntervalSince1970: 100)
        )
        let later = FileEntry(
            url: URL(fileURLWithPath: "/card/a.jpg"),
            relativePath: "a.jpg",
            size: 10,
            modificationDate: Date(timeIntervalSince1970: 200)
        )

        #expect(try PhotographerCardAnalyzer.preliminaryAnalysis(entries: [earlier, later]).fingerprint ==
                PhotographerCardAnalyzer.preliminaryAnalysis(entries: [later, earlier]).fingerprint)
    }
}
