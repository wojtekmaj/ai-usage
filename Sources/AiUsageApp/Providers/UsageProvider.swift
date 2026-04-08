import Foundation

@MainActor
protocol UsageProvider: AnyObject {
    var id: ProviderID { get }
    var sourceDescription: String { get }

    func currentAuthState() -> ProviderAuthState
    func refresh(now: Date) async -> ProviderSnapshot
    func clearAuth() throws
}