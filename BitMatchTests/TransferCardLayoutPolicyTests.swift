import Testing
@testable import BitMatch

struct TransferCardLayoutPolicyTests {
    @Test func activeTransferCardsStackBeforeTheirThreeColumnsBecomeCrowded() {
        #expect(TransferCardLayoutPolicy.presentation(for: 719) == .stacked)
        #expect(TransferCardLayoutPolicy.presentation(for: 720) == .horizontal)
    }
}
