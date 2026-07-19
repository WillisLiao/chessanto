import CompanionDomain
import Foundation

public enum CompanionMailboxAddress: Hashable, Sendable {
    case mac
    case phone
}

public enum CompanionMailboxError: Error, Equatable {
    case endpointUnavailable
}

public protocol CompanionMailbox: Sendable {
    func send(
        _ message: CompanionMessage,
        to address: CompanionMailboxAddress
    ) async throws

    func receive(
        for address: CompanionMailboxAddress
    ) async throws -> [CompanionMessage]
}

public actor InMemoryCompanionMailbox: CompanionMailbox {
    private var queues: [CompanionMailboxAddress: [CompanionMessage]] = [
        .mac: [],
        .phone: [],
    ]
    private var reachable: Set<CompanionMailboxAddress> = [.mac, .phone]

    public init() {}

    public func setReachable(
        _ isReachable: Bool,
        for address: CompanionMailboxAddress
    ) {
        if isReachable {
            reachable.insert(address)
        } else {
            reachable.remove(address)
        }
    }

    public func send(
        _ message: CompanionMessage,
        to address: CompanionMailboxAddress
    ) {
        queues[address, default: []].append(message)
    }

    public func receive(
        for address: CompanionMailboxAddress
    ) throws -> [CompanionMessage] {
        guard reachable.contains(address) else {
            throw CompanionMailboxError.endpointUnavailable
        }
        let messages = queues[address, default: []]
        queues[address] = []
        return messages
    }
}
