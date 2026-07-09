import Testing
@testable import AiUsageApp

struct ProviderIconAssetTests {
    @Test
    func resolvesProviderIconsFromAvailableBundles() {
        for provider in ProviderID.allCases {
            #expect(ProviderIconAsset.url(for: provider) != nil)
        }
    }
}
