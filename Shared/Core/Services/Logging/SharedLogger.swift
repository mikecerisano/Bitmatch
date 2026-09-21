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

      // All platforms log through os.Logger: interpolated values stay
      // private/redacted by default, and nothing spams stdout in Release.
      // Use a DEBUG print only when actively diagnosing on-device.
      static func info(_ message: String, category: Category = .general) {
          logger(for: category).info("\(message)")
      }

      static func debug(_ message: String, category: Category = .general) {
          logger(for: category).debug("\(message)")
      }

      static func warning(_ message: String, category: Category = .general) {
          logger(for: category).notice("\(message)")
      }

      static func error(_ message: String, category: Category = .error) {
          logger(for: category).error("\(message)")
      }
}
