import Foundation
import Testing
@testable import Chessanto

/// Live sandbox check (NEXT-SESSION-M6.md step 7's gate): proves the
/// sandboxed app can actually reach `127.0.0.1:11434`, not just that
/// `project.yml`'s `NSAllowsLocalNetworking`/network-client entitlement is
/// present. Runs only when explicitly requested (`LIVE=1`), same pattern as
/// CoachKit's `OllamaClientTests.liveRoundTripWithRealQwen3IfRequested`.
@MainActor
struct CoachServiceLiveTests {
    @Test func healthCheckReachesRealOllamaFromTheSandboxedApp() async throws {
        guard ProcessInfo.processInfo.environment["LIVE"] == "1" else { return }
        let service = CoachService()
        await service.checkHealth()
        guard case .reachable(let installed, _) = service.health else {
            Issue.record("expected .reachable, got \(service.health)")
            return
        }
        #expect(installed.contains("qwen3:0.6b"))
    }
}
