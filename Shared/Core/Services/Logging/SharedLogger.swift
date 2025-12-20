import Foundation
import os.log
import Foundation
import os.log

enum SharedLogger {
      enum Category: String {
          case general = "General"
          case transfer = "Transfer"
          case error = "Error"
          case ui = "UI"
      }

      private static let subsystem = "com.bitmatch.app"
      private static func logger(for category: Category) -> Logger {
          Logger(subsystem: subsystem, category: category.rawValue)
      }

      static func info(_ message: String, category: Category = .general) {
          #if os(iOS)
          print("ℹ️[\(category.rawValue)] \(message)")
          #else
          logger(for: category).info("\(message)")
          #endif
      }

      static func debug(_ message: String, category: Category = .general) {
          #if os(iOS)
          #if DEBUG
          print("🔍[\(category.rawValue)] \(message)")
          #endif
          #else
          logger(for: category).debug("\(message)")
          #endif
      }

      static func warning(_ message: String, category: Category = .general) {
          #if os(iOS)
          print("⚠️[\(category.rawValue)] \(message)")
          #else
          logger(for: category).notice("\(message)")
          #endif
      }

      static func error(_ message: String, category: Category = .error) {
          #if os(iOS)
          print("🚨[\(category.rawValue)] \(message)")
          #else
          logger(for: category).error("\(message)")
          #endif
      }
}
