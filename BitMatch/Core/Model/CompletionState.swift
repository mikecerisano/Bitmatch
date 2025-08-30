// Core/Model/CompletionState.swift
import Foundation

enum CompletionState: Equatable {
    case idle
    case success(message: String)
    case issues(message: String)
}