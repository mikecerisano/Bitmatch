// CompareStats.swift - What a folder comparison found.
import Foundation

struct CompareStats: Equatable {
    let onlyInLeftCount: Int
    let onlyInRightCount: Int
    let commonCount: Int
    let mismatchedCount: Int
    /// Relative paths behind the counts, sorted for stable display and export.
    /// Retained so a reported difference (e.g. one destination-only item from a
    /// camera-card offload) names the file instead of ending at a count.
    let onlyInLeftPaths: [String]
    let onlyInRightPaths: [String]
    let mismatchedPaths: [String]

    init(
        onlyInLeftCount: Int,
        onlyInRightCount: Int,
        commonCount: Int,
        mismatchedCount: Int,
        onlyInLeftPaths: [String] = [],
        onlyInRightPaths: [String] = [],
        mismatchedPaths: [String] = []
    ) {
        self.onlyInLeftCount = onlyInLeftCount
        self.onlyInRightCount = onlyInRightCount
        self.commonCount = commonCount
        self.mismatchedCount = mismatchedCount
        self.onlyInLeftPaths = onlyInLeftPaths
        self.onlyInRightPaths = onlyInRightPaths
        self.mismatchedPaths = mismatchedPaths
    }

    /// True only when both folders contain the same files with matching content.
    var isClean: Bool {
        onlyInLeftCount == 0 && onlyInRightCount == 0 && mismatchedCount == 0
    }
}
