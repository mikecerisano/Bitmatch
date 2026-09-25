// TransferEstimateModel.swift - Mac-only "Estimated time" above Start
//
// The only caller of DriveBenchmarkService. The thesis (step 5) replaces
// the benchmark with an estimate from observed copy speed; when that lands,
// only this file changes.
import Foundation
import Combine

@MainActor
final class TransferEstimateModel: ObservableObject {
    typealias Estimator = (_ source: URL, _ destinations: [URL], _ totalBytes: Int64, _ mode: VerificationMode) async -> TimeEstimate?

    @Published private(set) var estimate: TimeEstimate?
    @Published private(set) var isCalculating = false

    private let estimator: Estimator
    /// Each request gets a generation; only the latest may publish, so a
    /// slow benchmark for an old selection never overwrites a newer one.
    private var generation = 0

    init(estimator: @escaping Estimator = { source, destinations, totalBytes, mode in
        await DriveBenchmarkService.shared.estimateTransferTime(
            sourceURL: source,
            destinationURLs: destinations,
            totalBytes: totalBytes,
            verificationMode: mode
        )
    }) {
        self.estimator = estimator
    }

    func update(source: URL?, destinations: [URL], totalBytes: Int64?, mode: VerificationMode) {
        generation += 1
        let current = generation
        guard let source, !destinations.isEmpty, let totalBytes, totalBytes > 0 else {
            estimate = nil
            isCalculating = false
            return
        }
        isCalculating = true
        let estimator = self.estimator
        Task { [weak self] in
            let result = await estimator(source, destinations, totalBytes, mode)
            guard let self, current == self.generation else { return }
            self.estimate = result
            self.isCalculating = false
        }
    }
}
