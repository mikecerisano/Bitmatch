// ReportPrefsStore.swift - Report settings saved across launches
import Foundation

/// Loads and saves `ReportPrefs` with the keys the Mac has always used, so
/// Mac users keep their settings and iPad and iPhone now remember theirs
/// (thesis decision, step 3).
struct ReportPrefsStore {
    static let makeReportKey = "BitMatch_MakeReportEnabled"
    static let prefsKey = "BitMatch_ReportPrefs_JSON"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ReportPrefs {
        var prefs = ReportPrefs()
        if let data = defaults.data(forKey: Self.prefsKey) {
            do {
                prefs = try JSONDecoder().decode(ReportPrefs.self, from: data)
            } catch {
                SharedLogger.warning("Failed to load ReportPrefs, falling back to defaults: \(error)", category: .transfer)
                if defaults.object(forKey: Self.makeReportKey) != nil {
                    prefs.makeReport = defaults.bool(forKey: Self.makeReportKey)
                }
            }
        } else if defaults.object(forKey: Self.makeReportKey) != nil {
            // Older versions stored only makeReport.
            prefs.makeReport = defaults.bool(forKey: Self.makeReportKey)
        }
        return prefs
    }

    func save(_ prefs: ReportPrefs) {
        defaults.set(prefs.makeReport, forKey: Self.makeReportKey)
        do {
            defaults.set(try JSONEncoder().encode(prefs), forKey: Self.prefsKey)
        } catch {
            SharedLogger.error("Failed to persist ReportPrefs: \(error)", category: .transfer)
        }
    }
}
