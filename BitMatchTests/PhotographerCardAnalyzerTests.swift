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

    @Test func preliminaryAnalysisRetainsSortedAbsoluteSourcePaths() throws {
        let entries = [
            FileEntry(url: URL(fileURLWithPath: "/card/Z.JPG"), relativePath: "Z.JPG", size: 5, modificationDate: nil),
            FileEntry(url: URL(fileURLWithPath: "/card/A.ARW"), relativePath: "A.ARW", size: 10, modificationDate: nil)
        ]

        let analysis = try PhotographerCardAnalyzer.preliminaryAnalysis(entries: entries)

        #expect(analysis.sourcePaths == ["/card/A.ARW", "/card/Z.JPG"])
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

    @Test func preliminaryAnalysisCooperativelyObservesTaskCancellation() async {
        let entries = (0..<20_000).map { index in
            FileEntry(
                url: URL(fileURLWithPath: "/card/\(index).ARW"),
                relativePath: "DCIM/\(index).ARW",
                size: 100
            )
        }
        let task = Task.detached {
            try PhotographerCardAnalyzer.preliminaryAnalysis(entries: entries)
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected preliminary analysis to throw CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
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

    @Test func confirmedFingerprintIsDeterministicForSuccessfulVerifiedRows() throws {
        let a = ResultRow(
            path: "/card/A.ARW",
            status: "✅ Verified",
            size: 10,
            checksum: "aaa",
            destination: nil
        )
        let b = ResultRow(
            path: "/card/B.JPG",
            status: "✅ Verified",
            size: 5,
            checksum: "bbb",
            destination: nil
        )

        let forward = try PhotographerCardAnalyzer.confirmedFingerprint(results: [a, b])
        let reversed = try PhotographerCardAnalyzer.confirmedFingerprint(results: [b, a])

        #expect(forward == reversed)
        #expect(forward == "b85fb86ec3d1ff98f0445514ec75dc725575ce97383a61d3b6dd59a3fe71388e")
    }

    @Test func confirmedFingerprintRejectsNonSuccessRow() {
        let failed = ResultRow(
            path: "/card/A.ARW",
            status: "❌ Checksum mismatch",
            size: 10,
            checksum: "aaa",
            destination: nil
        )

        #expect(throws: CardAnalysisError.incompleteVerification) {
            try PhotographerCardAnalyzer.confirmedFingerprint(results: [failed])
        }
    }

    @Test func confirmedFingerprintRejectsSuccessfulRowWithoutChecksum() {
        let missingChecksum = ResultRow(
            path: "/card/A.ARW",
            status: "✅ Verified",
            size: 10,
            checksum: nil,
            destination: nil
        )

        #expect(throws: CardAnalysisError.incompleteVerification) {
            try PhotographerCardAnalyzer.confirmedFingerprint(results: [missingChecksum])
        }
    }
}
