import CompanionDomain
import CompanionSecurity
import CryptoKit
import Foundation

public protocol CompanionCloudRecordTransport: Sendable {
    func enqueue(_ record: CompanionCloudRecord) async throws
}

extension CompanionCKSyncEngine: CompanionCloudRecordTransport {}

public enum SecureCompanionCloudMailboxError: Error, Equatable {
    case unapprovedOrRevokedSender
    case mismatchedAuthenticatedHeader
    case mismatchedRecordType
}

public actor SecureCompanionCloudMailbox {
    public typealias SigningKeyResolver =
        @Sendable (CompanionDeviceID) async -> Curve25519.Signing.PublicKey?

    private let senderDeviceID: CompanionDeviceID
    private let signingKey: Curve25519.Signing.PrivateKey
    private let contentKey: SymmetricKey
    private let transport: any CompanionCloudRecordTransport
    private let signingKeyResolver: SigningKeyResolver
    private let inbox = SecureEnvelopeInbox()

    public init(
        senderDeviceID: CompanionDeviceID,
        signingKey: Curve25519.Signing.PrivateKey,
        contentKey: SymmetricKey,
        transport: any CompanionCloudRecordTransport,
        signingKeyResolver: @escaping SigningKeyResolver
    ) {
        self.senderDeviceID = senderDeviceID
        self.signingKey = signingKey
        self.contentKey = contentKey
        self.transport = transport
        self.signingKeyResolver = signingKeyResolver
    }

    public func send(
        _ message: CompanionMessage,
        to recipient: EndpointID
    ) async throws {
        let type = recordType(for: message)
        let messageID = messageIdentifier(for: message)
        let recordID = recordIdentifier(for: message, type: type)
        let header = AuthenticatedEnvelopeHeader(
            recordID: recordID,
            protocolVersion: .v1,
            messageID: messageID,
            sender: senderDeviceID,
            recipient: recipient
        )
        let envelope = try CompanionEnvelopeCrypto.seal(
            CanonicalCoding.encode(message),
            header: header,
            contentKey: contentKey,
            signingKey: signingKey
        )
        try await transport.enqueue(
            CompanionCloudRecordMapper.map(
                envelope,
                type: type
            )
        )
    }

    public func receive(
        _ record: CompanionCloudRecord,
        expectedRecipient: EndpointID
    ) async throws -> CompanionMessage {
        let envelope = try CompanionCloudRecordMapper.envelope(from: record)
        guard
            envelope.header.recordID == record.recordName,
            record.queryableFields["protocolVersion"]
                == String(envelope.header.protocolVersion.rawValue),
            record.queryableFields["messageID"]
                == envelope.header.messageID,
            record.queryableFields["sender"]
                == envelope.header.sender.rawValue,
            record.queryableFields["recipient"]
                == envelope.header.recipient.rawValue
        else {
            throw SecureCompanionCloudMailboxError
                .mismatchedAuthenticatedHeader
        }
        guard let senderKey = await signingKeyResolver(envelope.header.sender) else {
            throw SecureCompanionCloudMailboxError.unapprovedOrRevokedSender
        }
        let payload = try await inbox.open(
            envelope,
            expectedRecipient: expectedRecipient,
            contentKey: contentKey,
            senderSigningKey: senderKey
        )
        let message = try CanonicalCoding.decode(
            CompanionMessage.self,
            from: payload
        )
        guard recordType(for: message) == record.type else {
            throw SecureCompanionCloudMailboxError.mismatchedRecordType
        }
        return message
    }

    private func recordType(
        for message: CompanionMessage
    ) -> CompanionCloudRecordType {
        switch message {
        case .gameCatalog:
            return .gameCatalog
        case .analysisRequest:
            return .analysisRequest
        case .analysisCancellation:
            return .analysisCancellation
        case .analysisStatus:
            return .analysisStatus
        case .report:
            return .reportSnapshot
        }
    }

    private func messageIdentifier(for message: CompanionMessage) -> String {
        switch message {
        case .gameCatalog(let catalog):
            return "catalog-\(catalog.version)-\(catalog.generatedAt.timeIntervalSince1970)"
        case .analysisRequest(let request):
            return request.id.rawValue
        case .analysisCancellation(let cancellation):
            return cancellation.id
        case .analysisStatus(let status):
            return [
                status.requestID.rawValue,
                status.state.rawValue,
                String(status.updatedAt.timeIntervalSince1970),
            ].joined(separator: "-")
        case .report(let report):
            return report.id.rawValue
        }
    }

    private func recordIdentifier(
        for message: CompanionMessage,
        type: CompanionCloudRecordType
    ) -> String {
        switch message {
        case .analysisStatus(let status):
            return "status-\(status.requestID.rawValue)"
        case .gameCatalog:
            return "game-catalog-current"
        default:
            return "\(type.rawValue.lowercased())-\(messageIdentifier(for: message))"
        }
    }
}
