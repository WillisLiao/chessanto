import CompanionDomain
import CompanionSecurity
import CryptoKit
import Foundation
import Testing
@testable import ChessantoMobile

@Suite("Offline report cache")
struct OfflineReportCacheTests {
    @Test("report is encrypted on disk and survives an offline relaunch")
    func reportIsEncryptedAndSurvivesRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let secrets = MemorySecretStore()
        let first = OfflineReportCache(rootURL: root, secrets: secrets)
        let report = makeReport()

        try await first.save(report)
        let storedURL = try #require(
            FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            ).first
        )
        let ciphertext = try Data(contentsOf: storedURL)
        #expect(String(data: ciphertext, encoding: .utf8)?.contains(report.pgn) != true)

        let reopened = OfflineReportCache(rootURL: root, secrets: secrets)
        #expect(try await reopened.report(id: report.id) == report)
        #expect(try await reopened.reports().map { $0.id } == [report.id])
    }

    @Test("deleting a downloaded report removes only the companion copy")
    func deletingDownloadedReportRemovesCompanionCopy() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = OfflineReportCache(
            rootURL: root,
            secrets: MemorySecretStore()
        )
        let report = makeReport()

        try await cache.save(report)
        try await cache.delete(id: report.id)

        #expect(try await cache.report(id: report.id) == nil)
    }

    private func makeReport() -> PortableAnalysisReport {
        PortableAnalysisReport(
            protocolVersion: .v1,
            id: ReportID("report-1"),
            gameID: CompanionGameID("game-1"),
            generatedAt: Date(timeIntervalSince1970: 100),
            analysisQuality: .standard,
            metadata: PortableGameMetadata(
                white: "Willis",
                black: "Coach",
                result: "1-0",
                playedAt: Date(timeIntervalSince1970: 50),
                timeControl: "600"
            ),
            pgn: "1. Nf3 Nf6",
            positions: [
                PortablePosition(
                    ply: 0,
                    fen: "8/8/8/8/8/8/8/8 w - - 0 1",
                    playedSAN: nil
                )
            ],
            evaluations: [],
            rankedLines: [],
            classifications: [],
            opening: nil,
            keyMoments: [],
            takeaways: ["Develop before attacking."]
        )
    }
}

private final class MemorySecretStore: SecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func save(_ data: Data, account: String) throws {
        lock.withLock {
            values[account] = data
        }
    }

    func load(account: String) throws -> Data? {
        lock.withLock {
            values[account]
        }
    }

    func remove(account: String) throws {
        _ = lock.withLock {
            values.removeValue(forKey: account)
        }
    }
}
