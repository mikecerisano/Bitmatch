// Core/Models/AppMode.swift
import Foundation

enum AppMode: String, CaseIterable {
    case copyAndVerify = "Copy & Verify"
    case compareFolders = "Compare Folders"
    case masterReport = "Master Report"
    
    var icon: String {
        switch self {
        case .copyAndVerify: return "arrow.right.doc.on.clipboard"
        case .compareFolders: return "arrow.left.arrow.right"
        case .masterReport: return "doc.richtext"
        }
    }
    
    var shortTitle: String {
        switch self {
        case .copyAndVerify: return "Copy to Backups"
        case .compareFolders: return "Compare Folders"
        case .masterReport: return "Master Report"
        }
    }
    
    var description: String {
        switch self {
        case .copyAndVerify: return "Copy camera cards to multiple backups with verification"
        case .compareFolders: return "Compare two folders to verify they match"
        case .masterReport: return "Generate a master report of all today's transfers"
        }
    }
}
