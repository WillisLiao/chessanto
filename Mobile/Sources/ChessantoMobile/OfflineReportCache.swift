import CompanionDomain
import CompanionSecurity
import CryptoKit
import Foundation

enum OfflineReportCacheError: Error {
    case malformedCiphertext
}

/// The phone's report archive is independent from the Mac database.
///
/// Each report is app-encrypted with a device-only Keychain key before it is
/// written under iOS data protection, so airplane-mode reading needs no Mac
/// or CloudKit connection.
actor OfflineReportCache {
    private static let keyAccount = "offline-report-content-key-v1"

    private let rootURL: URL
    private let secrets: any SecretStoring

    init(
        rootURL: URL = OfflineReportCache.defaultRootURL(),
        secrets: any SecretStoring = KeychainSecretStore(
            service: "com.chessanto.companion.offline-reports"
        )
    ) {
        self.rootURL = rootURL
        self.secrets = secrets
    }

    func save(_ report: PortableAnalysisReport) throws {
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        let sealed = try AES.GCM.seal(
            CanonicalCoding.encode(report),
            using: contentKey()
        )
        guard let combined = sealed.combined else {
            throw OfflineReportCacheError.malformedCiphertext
        }
        let url = fileURL(for: report.id)
        try combined.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [
                .protectionKey:
                    FileProtectionType.completeUntilFirstUserAuthentication
            ],
            ofItemAtPath: url.path
        )
    }

    func reports() throws -> [PortableAnalysisReport] {
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "chessanto-report" }
        .compactMap { try? decrypt(at: $0) }
        .sorted { $0.generatedAt > $1.generatedAt }
    }

    func report(id: ReportID) throws -> PortableAnalysisReport? {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try decrypt(at: url)
    }

    func delete(id: ReportID) throws {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func decrypt(at url: URL) throws -> PortableAnalysisReport {
        let combined = try Data(contentsOf: url)
        let box: AES.GCM.SealedBox
        do {
            box = try AES.GCM.SealedBox(combined: combined)
        } catch {
            throw OfflineReportCacheError.malformedCiphertext
        }
        let plaintext = try AES.GCM.open(box, using: contentKey())
        return try CanonicalCoding.decode(
            PortableAnalysisReport.self,
            from: plaintext
        )
    }

    private func contentKey() throws -> SymmetricKey {
        if let data = try secrets.load(account: Self.keyAccount) {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try secrets.save(data, account: Self.keyAccount)
        return key
    }

    private func fileURL(for id: ReportID) -> URL {
        rootURL
            .appendingPathComponent(id.rawValue)
            .appendingPathExtension("chessanto-report")
    }

    private nonisolated static func defaultRootURL() -> URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("OfflineReports", isDirectory: true)
    }
}
