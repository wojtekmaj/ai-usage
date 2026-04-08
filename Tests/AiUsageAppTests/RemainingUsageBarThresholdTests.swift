import Testing
@testable import AiUsageApp

struct RemainingUsageBarThresholdTests {
    @Test
    func usesCriticalThresholdBelowTenPercent() {
        #expect(RemainingUsageBarThreshold(for: 0.099) == .critical)
    }

    @Test
    func usesWarningThresholdBelowThirtyPercent() {
        #expect(RemainingUsageBarThreshold(for: 0.29) == .warning)
    }

    @Test
    func keepsTenPercentInWarningBand() {
        #expect(RemainingUsageBarThreshold(for: 0.1) == .warning)
    }

    @Test
    func keepsThirtyPercentInHealthyBand() {
        #expect(RemainingUsageBarThreshold(for: 0.3) == .healthy)
    }

    @Test
    func defaultsMissingValuesToHealthy() {
        #expect(RemainingUsageBarThreshold(for: nil) == .healthy)
    }
}
