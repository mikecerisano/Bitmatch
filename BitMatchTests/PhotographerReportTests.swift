import Foundation
import Testing
@testable import BitMatch

struct PhotographerReportTests {
    private let cardID = UUID(uuidString: "00000000-0000-0000-0000-000000000702")!
    private let eventDate = Date(timeIntervalSince1970: 1_752_499_800)
    private let locallySafeAt = Date(timeIntervalSince1970: 1_752_503_400)

    @Test func payloadEncodesCompletePhotographyProvenanceAndEveryAuthoritativeRow() throws {
        let payload = try PhotographerReportPayload.make(context: context(), results: results())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let card = try #require(object["card"] as? [String: Any])
        let provenance = try #require(card["provenance"] as? [String: Any])
        let companionCounts = try #require(object["companionCounts"] as? [String: Any])
        let encodedResults = try #require(object["results"] as? [[String: Any]])

        #expect(object["jobName"] as? String == "Smith Wedding")
        #expect(object["clientName"] as? String == "Smith")
        #expect(object["eventType"] as? String == "Wedding")
        #expect(object["eventDate"] as? String == "2025-07-14T13:30:00Z")
        #expect(provenance["photographerName"] as? String == "Mike")
        #expect(provenance["cameraName"] as? String == "Sony A7 IV")
        #expect(provenance["cardNumber"] as? Int == 1)
        #expect(card["renderedRelativePath"] as? String == "2025-07-14_Smith-Wedding/Originals/Mike/Sony-A7-IV/Card-001")
        #expect(provenance["preliminaryFingerprint"] as? String == "preliminary-fingerprint")
        #expect(provenance["confirmedFingerprint"] as? String == "confirmed-fingerprint")
        #expect(companionCounts["raw"] as? Int == 1)
        #expect(companionCounts["jpeg"] as? Int == 1)
        #expect(companionCounts["sidecar"] as? Int == 1)
        #expect(object["requiredLocalCopyCount"] as? Int == 2)
        #expect(object["verifiedDestinationCount"] as? Int == 2)
        #expect(object["locallySafeAt"] as? String == "2025-07-14T14:30:00Z")
        #expect(object["warnings"] as? [String] == ["Duplicate fingerprint matches Card 004."])
        #expect(encodedResults.count == 2)
        #expect(encodedResults[0]["checksum"] as? String == "raw-checksum")
        #expect(encodedResults[0]["successful"] as? Bool == true)
        #expect(encodedResults[1]["path"] as? String == "/CARD/DCIM/100MEDIA/DSC0001.XMP")
        #expect(encodedResults[1]["checksum"] == nil)
        #expect(encodedResults[1]["successful"] as? Bool == false)
    }

    @Test func payloadThrowsWhenActiveCardIsNotInAuthoritativeJob() {
        var missing = context()
        missing = PhotographerReportContext(
            job: missing.job,
            cardIngestID: UUID(),
            analysis: missing.analysis,
            verifiedDestinationCount: missing.verifiedDestinationCount,
            warnings: missing.warnings
        )

        #expect(throws: PhotographerReportError.cardNotFound) {
            try PhotographerReportPayload.make(context: missing, results: results())
        }
    }

    @Test func enhancedJSONPreservesLegacyFieldsWithNilPhotographyContextExceptVersionBump() throws {
        let report = try ReportExporter.makeEnhancedJSONReport(
            results: results(),
            jobID: UUID(uuidString: "00000000-0000-0000-0000-000000000799")!,
            started: eventDate,
            finished: locallySafeAt,
            mode: .copyAndVerify,
            sourceURL: URL(fileURLWithPath: "/CARD"),
            destinationURLs: [URL(fileURLWithPath: "/Volumes/LOCAL")],
            fileCount: 2,
            matchCount: 1,
            totalBytesProcessed: 101,
            duration: 3_600,
            workers: 4,
            prefs: ReportPrefs(),
            photographerContext: nil
        )

        #expect(report.reportVersion == "3.0")
        #expect(report.photographyJob == nil)
        #expect(report.source.path == "/CARD")
        #expect(report.statistics.totalFiles == 2)
        #expect(report.statistics.matches == 1)
        #expect(report.results.map(\.status) == ["✅ Verified", "⚠️ Checksum Missing"])
    }

    @Test func nilPhotographyContextLeavesNewCSVProvenanceColumnsEmpty() throws {
        let csv = try ReportExporter.makeEnhancedCSV(
            results: results(),
            started: eventDate,
            duration: 3_600,
            filesPerSecond: 1,
            photographerContext: nil
        )
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)

        #expect(lines.first == "Status,File Path,Target Path,Job,Photographer,Camera,Card,Package Path,Details,Timestamp")
        #expect(lines[1].contains(",,,,,Verified,"))
        #expect(lines[2].contains(",,,,,⚠️ Checksum Missing,"))
    }

    @Test func enhancedJSONAndCSVCarryPhotographyContextWithoutDroppingFailuresOrSidecars() throws {
        let report = try ReportExporter.makeEnhancedJSONReport(
            results: results(),
            jobID: UUID(),
            started: eventDate,
            finished: locallySafeAt,
            mode: .copyAndVerify,
            sourceURL: URL(fileURLWithPath: "/CARD"),
            destinationURLs: [URL(fileURLWithPath: "/Volumes/LOCAL")],
            fileCount: 2,
            matchCount: 1,
            totalBytesProcessed: 101,
            duration: 3_600,
            workers: 4,
            prefs: ReportPrefs(),
            photographerContext: context()
        )
        let csv = try ReportExporter.makeEnhancedCSV(
            results: results(),
            started: eventDate,
            duration: 3_600,
            filesPerSecond: 1,
            photographerContext: context()
        )

        #expect(report.photographyJob?.results.count == 2)
        #expect(report.photographyJob?.results.last?.successful == false)
        #expect(csv.hasPrefix("Status,File Path,Target Path,Job,Photographer,Camera,Card,Package Path,Details,Timestamp\n"))
        #expect(csv.contains("Smith Wedding,Mike,Sony A7 IV,Card 001,2025-07-14_Smith-Wedding/Originals/Mike/Sony-A7-IV/Card-001"))
        #expect(csv.contains("⚠️ Checksum Missing"))
        #expect(csv.contains("DSC0001.XMP"))
    }

    @Test func payloadEncodingIsDeterministicForIdenticalInputs() throws {
        let payload = try PhotographerReportPayload.make(context: context(), results: results())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        #expect(try encoder.encode(payload) == encoder.encode(payload))
    }

    @Test func staleStartContextIsFinalizedOnlyFromExactAuthoritativeResults() throws {
        let context = staleContext()
        let rows = exactTwoDestinationResults()
        let expectedFingerprint = try PhotographerCardAnalyzer.confirmedFingerprint(
            results: Array(rows.prefix(2)).sorted { $0.path < $1.path }
        )

        let payload = try PhotographerReportPayload.make(
            context: context,
            results: rows,
            finishedAt: locallySafeAt
        )

        #expect(payload.card.localState == .locallySafe)
        #expect(payload.card.locallySafeAt == locallySafeAt)
        #expect(payload.card.provenance.confirmedFingerprint == expectedFingerprint)
        #expect(payload.verifiedDestinationCount == 2)
        #expect(payload.card.verifiedDestinationCount == 2)
        #expect(payload.results.count == 4)
    }

    @Test func staleStartContextWithMissingSidecarRemainsUnsafeAndRetainsFailure() throws {
        let context = staleContext()
        var rows = exactTwoDestinationResults()
        rows.removeLast()
        rows.append(ResultRow(
            path: "/CARD/DCIM/100MEDIA/DSC0001.XMP",
            status: "⚠️ Checksum Missing",
            size: 1,
            checksum: nil,
            destination: "LOCAL-B",
            destinationPath: "/Volumes/LOCAL-B/2025-07-14_Smith-Wedding/Originals/Mike/Sony-A7-IV/Card-001/DSC0001.XMP"
        ))

        let payload = try PhotographerReportPayload.make(
            context: context,
            results: rows,
            finishedAt: locallySafeAt
        )

        #expect(payload.card.localState == .issues)
        #expect(payload.card.locallySafeAt == nil)
        #expect(payload.card.provenance.confirmedFingerprint == nil)
        #expect(payload.verifiedDestinationCount == 0)
        #expect(payload.results.count == 4)
        #expect(payload.results.last?.successful == false)
        #expect(payload.results.last?.checksum == nil)
    }

    private func context() -> PhotographerReportContext {
        let photographerID = UUID(uuidString: "00000000-0000-0000-0000-000000000701")!
        let card = CardIngest(
            id: cardID,
            provenance: CardProvenance(
                photographerID: photographerID,
                photographerName: "Mike",
                cameraName: "Sony A7 IV",
                cardNumber: 1,
                preliminaryFingerprint: "preliminary-fingerprint",
                confirmedFingerprint: "confirmed-fingerprint"
            ),
            sourceDisplayName: "CARD",
            renderedRelativePath: "2025-07-14_Smith-Wedding/Originals/Mike/Sony-A7-IV/Card-001",
            localState: .locallySafe,
            startedAt: eventDate,
            locallySafeAt: locallySafeAt,
            fileCount: 3,
            totalBytes: 151,
            verifiedDestinationCount: 2
        )
        let job = PhotographerJob(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000700")!,
            eventDate: eventDate,
            clientName: "Smith",
            jobName: "Smith Wedding",
            eventType: .wedding,
            photographers: [PhotographerIdentity(id: photographerID, name: "Mike")],
            recipe: .wedding,
            requiredLocalCopyCount: 2,
            cardIngests: [card],
            createdAt: eventDate,
            updatedAt: locallySafeAt
        )
        let analysis = CardAnalysis(
            fingerprint: "preliminary-fingerprint",
            fileCount: 3,
            totalBytes: 151,
            companionGroups: [
                PhotoCompanionGroup(
                    stem: "dcim/100media/dsc0001",
                    rawPaths: ["DCIM/100MEDIA/DSC0001.ARW"],
                    jpegPaths: ["DCIM/100MEDIA/DSC0001.JPG"],
                    sidecarPaths: ["DCIM/100MEDIA/DSC0001.XMP"]
                )
            ]
        )
        return PhotographerReportContext(
            job: job,
            cardIngestID: cardID,
            analysis: analysis,
            verifiedDestinationCount: 2,
            warnings: ["Duplicate fingerprint matches Card 004."]
        )
    }

    private func results() -> [ResultRow] {
        [
            ResultRow(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000710")!,
                path: "/CARD/DCIM/100MEDIA/DSC0001.ARW",
                status: "✅ Verified",
                size: 100,
                checksum: "raw-checksum",
                destination: "LOCAL",
                destinationPath: "/Volumes/LOCAL/package/DSC0001.ARW"
            ),
            ResultRow(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000711")!,
                path: "/CARD/DCIM/100MEDIA/DSC0001.XMP",
                status: "⚠️ Checksum Missing",
                size: 1,
                checksum: nil,
                destination: "LOCAL",
                destinationPath: "/Volumes/LOCAL/package/DSC0001.XMP"
            )
        ]
    }

    private func staleContext() -> PhotographerReportContext {
        let photographerID = UUID(uuidString: "00000000-0000-0000-0000-000000000721")!
        let card = CardIngest(
            id: cardID,
            provenance: CardProvenance(
                photographerID: photographerID,
                photographerName: "Mike",
                cameraName: "Sony A7 IV",
                cardNumber: 1,
                preliminaryFingerprint: "preliminary-fingerprint",
                confirmedFingerprint: nil
            ),
            sourceDisplayName: "CARD",
            renderedRelativePath: "2025-07-14_Smith-Wedding/Originals/Mike/Sony-A7-IV/Card-001",
            localState: .notStarted,
            startedAt: nil,
            locallySafeAt: nil,
            fileCount: 2,
            totalBytes: 101,
            verifiedDestinationCount: 0
        )
        let job = PhotographerJob(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000720")!,
            eventDate: eventDate,
            clientName: "Smith",
            jobName: "Smith Wedding",
            eventType: .wedding,
            photographers: [PhotographerIdentity(id: photographerID, name: "Mike")],
            recipe: .wedding,
            requiredLocalCopyCount: 2,
            cardIngests: [card],
            createdAt: eventDate,
            updatedAt: eventDate
        )
        return PhotographerReportContext(
            job: job,
            cardIngestID: cardID,
            analysis: CardAnalysis(
                fingerprint: "preliminary-fingerprint",
                fileCount: 2,
                totalBytes: 101,
                companionGroups: [
                    PhotoCompanionGroup(
                        stem: "dcim/100media/dsc0001",
                        rawPaths: ["DCIM/100MEDIA/DSC0001.ARW"],
                        jpegPaths: [],
                        sidecarPaths: ["DCIM/100MEDIA/DSC0001.XMP"]
                    )
                ],
                sourcePaths: [
                    "/CARD/DCIM/100MEDIA/DSC0001.ARW",
                    "/CARD/DCIM/100MEDIA/DSC0001.XMP"
                ]
            ),
            verifiedDestinationCount: 0,
            warnings: ["Duplicate fingerprint matches Card 004."]
        )
    }

    private func exactTwoDestinationResults() -> [ResultRow] {
        (["LOCAL-A", "LOCAL-B"] as [String]).flatMap { destination in
            [
                ResultRow(
                    path: "/CARD/DCIM/100MEDIA/DSC0001.ARW",
                    status: "✅ Verified",
                    size: 100,
                    checksum: "raw-checksum",
                    destination: destination,
                    destinationPath: "/Volumes/\(destination)/2025-07-14_Smith-Wedding/Originals/Mike/Sony-A7-IV/Card-001/DSC0001.ARW"
                ),
                ResultRow(
                    path: "/CARD/DCIM/100MEDIA/DSC0001.XMP",
                    status: "✅ Verified",
                    size: 1,
                    checksum: "xmp-checksum",
                    destination: destination,
                    destinationPath: "/Volumes/\(destination)/2025-07-14_Smith-Wedding/Originals/Mike/Sony-A7-IV/Card-001/DSC0001.XMP"
                )
            ]
        }
    }
}
