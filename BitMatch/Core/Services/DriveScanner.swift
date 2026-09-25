// Core/Services/DriveScanner.swift
import Foundation

/// Mac entry point for the Master Report scan. The rules live in the shared
/// `ReportScanner`, so the Mac and iPad/iPhone find and judge reports alike.
enum DriveScanner {
    static func scanForBitMatchReports(at rootURL: URL, day: Date = Date()) async -> [TransferCard] {
        await ReportScanner.scan(at: rootURL, day: day)
    }
}
