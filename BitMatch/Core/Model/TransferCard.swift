// Core/Model/TransferCard.swift
import Foundation

struct TransferCard: Identifiable {
    let id = UUID()
    let cameraName: String
    let cameraIcon: String
    let totalSize: Int64
    let fileCount: Int
    let rolls: Int
    let sourcePath: String
    let destinationPaths: [String]
    let timestamp: Date
    let verified: Bool
    let metadata: TransferMetadata?
}