import Foundation
import Combine

/// How a finished Master Report left the app.
enum MasterReportDelivery: Equatable {
    /// Written to this file (the Mac save panel), with a JSON file beside it.
    case saved(URL)
    /// Handed to the share sheet, and the person finished sharing or saving it.
    case shared
}

/// The state behind the one Master Report screen (UI plan step 4.10): the
/// chosen folder and day, the scan, what was found and selected, and
/// generating the report. Choosing a folder, saving and sharing are platform
/// work, passed in as closures, so this model runs the same on every device.
@MainActor
final class MasterReportModel: ObservableObject {
    typealias ScanFunction = (URL, Date) async -> ReportScanner.ScanResult
    typealias Renderer = @MainActor ([TransferCard], SharedReportGenerationService.ReportConfiguration) async throws -> MasterReportResult
    /// Saves or shares the rendered report. Returns nil when the person
    /// cancelled, and throws when writing failed.
    typealias Deliver = @MainActor (_ result: MasterReportResult, _ suggestedName: String) async throws -> MasterReportDelivery?

    enum Phase: Equatable {
        /// No folder scanned yet.
        case idle
        case scanning
        /// A scan finished; `cards` and `skipped` hold what it found.
        case scanned
    }

    enum Generation: Equatable {
        case idle
        case generating
        /// Success, set only after the platform's write or share succeeded.
        case delivered(MasterReportDelivery)
        case failed(String)
    }

    @Published private(set) var location: URL?
    /// The day whose reports are listed. Defaults to today; changing it
    /// scans the chosen folder again.
    @Published var day: Date {
        didSet {
            guard !calendar.isDate(day, inSameDayAs: oldValue) else { return }
            scan()
        }
    }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var cards: [TransferCard] = []
    @Published private(set) var skipped: [ReportScanner.SkippedReport] = []
    @Published private(set) var selection: Set<UUID> = []
    @Published private(set) var generation: Generation = .idle

    private let calendar: Calendar
    private let scanner: ScanFunction
    private let renderer: Renderer
    private var scanTask: Task<Void, Never>?
    /// Only the newest scan may publish results; an older one that finishes
    /// late is dropped.
    private var activeScanID: UUID?

    init(
        day: Date = Date(),
        calendar: Calendar = .current,
        scanner: ScanFunction? = nil,
        renderer: Renderer? = nil
    ) {
        self.day = day
        self.calendar = calendar
        self.scanner = scanner ?? { url, day in
            await ReportScanner.scanReports(at: url, day: day, calendar: calendar)
        }
        self.renderer = renderer ?? { cards, configuration in
            try await SharedReportGenerationService().generateMasterReport(
                transfers: cards,
                configuration: configuration
            )
        }
    }

    // MARK: - Derived

    var groups: [MasterReportCameraGroup] { MasterReportPresentation.groups(cards) }
    var selectedCards: [TransferCard] { cards.filter { selection.contains($0.id) } }
    var selectedTotals: MasterReportTotals { MasterReportPresentation.totals(selectedCards) }
    var isScanning: Bool { phase == .scanning }
    var isGenerating: Bool { generation == .generating }
    var isToday: Bool { calendar.isDateInToday(day) }

    func presentation(deliverVerb: String) -> MasterReportPresentation {
        MasterReportPresentation.make(
            hasLocation: location != nil,
            isScanning: isScanning,
            foundCount: cards.count,
            selectedCount: selection.count,
            isGenerating: isGenerating,
            deliverVerb: deliverVerb
        )
    }

    func isSelected(_ card: TransferCard) -> Bool { selection.contains(card.id) }

    func isFullySelected(_ group: MasterReportCameraGroup) -> Bool {
        group.cards.allSatisfy { selection.contains($0.id) }
    }

    // MARK: - Scanning

    /// Scans `url` for the chosen day's reports.
    @discardableResult
    func choose(_ url: URL) -> Task<Void, Never>? {
        location = url
        return scan()
    }

    /// Scans the chosen folder again. A scan already running is cancelled,
    /// and its results are never shown.
    @discardableResult
    func scan() -> Task<Void, Never>? {
        guard let location else { return nil }
        scanTask?.cancel()
        let scanID = UUID()
        activeScanID = scanID
        phase = .scanning
        generation = .idle
        let day = self.day
        let scanner = self.scanner
        let task = Task { [weak self] in
            let result = await scanner(location, day)
            guard let self, self.activeScanID == scanID else { return }
            self.cards = result.cards
            self.skipped = result.skipped
            // Everything found is included until the person says otherwise.
            self.selection = Set(result.cards.map(\.id))
            self.phase = .scanned
            self.scanTask = nil
        }
        scanTask = task
        return task
    }

    /// Stops the scan and shows nothing from it.
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        activeScanID = nil
        cards = []
        skipped = []
        selection = []
        phase = .idle
    }

    /// The task of the scan in progress, for tests.
    var currentScan: Task<Void, Never>? { scanTask }

    // MARK: - Selection

    func toggle(_ card: TransferCard) {
        if selection.contains(card.id) {
            selection.remove(card.id)
        } else {
            selection.insert(card.id)
        }
        generation = .idle
    }

    func setGroup(_ group: MasterReportCameraGroup, included: Bool) {
        let ids = group.cards.map(\.id)
        if included {
            selection.formUnion(ids)
        } else {
            selection.subtract(ids)
        }
        generation = .idle
    }

    // MARK: - Generating

    /// Renders the selected transfers and hands the result to `deliver`.
    /// Success is recorded only once `deliver` returns without throwing;
    /// a cancelled save or share records nothing.
    func generate(
        configuration: SharedReportGenerationService.ReportConfiguration,
        deliver: Deliver
    ) async {
        let chosen = selectedCards
        guard !chosen.isEmpty, !isGenerating, !isScanning else { return }
        generation = .generating
        do {
            let result = try await renderer(chosen, configuration)
            guard let delivery = try await deliver(result, MasterReportPresentation.fileName(for: day, calendar: calendar)) else {
                generation = .idle
                return
            }
            generation = .delivered(delivery)
        } catch {
            SharedLogger.error("Master Report failed: \(error)", category: .transfer)
            generation = .failed(error.localizedDescription)
        }
    }
}
