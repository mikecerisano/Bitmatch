import SwiftUI
import CoreGraphics
import BitMatchEngine

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Renders the shared `ReportView` into a paginated PDF, the same way on
/// every platform (THESIS Promise 5, "one app everywhere", and the decision
/// of 2026-09-25: "iPad and iPhone get a PDF report too"). `ReportExporter`
/// hands this the same `ReportSummary`/`ResultRow` data it writes into the
/// CSV and JSON, so the PDF states only what those files state.
enum ReportPDFRenderer {
    static let pageWidth: CGFloat = 612
    static let pageHeight: CGFloat = 792

    @MainActor
    static func renderPDF(summary: ReportSummary, results: [ResultRow]) -> Data {
        let view = ReportView(s: summary, rows: results)
        let renderer = ImageRenderer(content: view)

        // Let the view determine its own height.
        renderer.proposedSize = ProposedViewSize(width: pageWidth, height: nil)
        if renderer.scale == 0 {
            #if os(macOS)
            renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
            #else
            renderer.scale = UIScreen.main.scale
            #endif
        }

        // Get the actual rendered size from the CGImage.
        let totalHeight: CGFloat
        if let cgImage = renderer.cgImage {
            // CGImage height is in pixels, need to account for scale.
            let scale = renderer.scale > 0 ? renderer.scale : 2.0
            totalHeight = CGFloat(cgImage.height) / scale
        } else {
            totalHeight = pageHeight
        }
        let pageCount = max(1, Int(ceil(totalHeight / pageHeight)))

        let pdfMetadata = [
            kCGPDFContextCreator: "BitMatch",
            kCGPDFContextTitle: "BitMatch Verification Report"
        ] as CFDictionary

        let mutableData = NSMutableData()
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData) else {
            return Data()
        }

        var mediaBox = CGRect(origin: .zero, size: CGSize(width: pageWidth, height: pageHeight))
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, pdfMetadata) else {
            return Data()
        }

        // CoreGraphics' origin is bottom-left, so the view's top sits at
        // y = totalHeight. Page N shows the band N page-heights below that
        // top; the last page is short and its gap falls at the bottom.
        for pageIndex in 0..<pageCount {
            context.beginPDFPage(nil)
            context.saveGState()

            let yOffset = totalHeight - CGFloat(pageIndex + 1) * pageHeight
            context.translateBy(x: 0, y: -yOffset)

            renderer.render { _, renderFunc in
                renderFunc(context)
            }

            context.restoreGState()
            context.endPDFPage()
        }

        context.closePDF()
        return mutableData as Data
    }
}
