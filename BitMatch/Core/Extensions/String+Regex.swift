// Core/Extensions/String+Regex.swift
import Foundation

extension String {
    /// Check if string matches a regular expression pattern
    func matches(_ regex: String) -> Bool {
        return self.range(of: regex, options: .regularExpression, range: nil, locale: nil) != nil
    }
}