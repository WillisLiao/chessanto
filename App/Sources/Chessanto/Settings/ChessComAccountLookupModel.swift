import ChessComKit
import Foundation

protocol ChessComAccountLookingUp: Sendable {
    func account(username: String) async throws -> ChessComAccount
}

extension ChessComClient: ChessComAccountLookingUp {}

@MainActor
final class ChessComAccountLookupModel: ObservableObject {
    enum State: Equatable {
        case idle
        case lookingUp(String)
        case candidate(ChessComAccount)
        case failed(query: String, message: String)
        case confirmed(ChessComAccount)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var confirmedCandidate: ChessComAccount?

    private let lookup: any ChessComAccountLookingUp
    private var generation = 0

    init(lookup: any ChessComAccountLookingUp = ChessComClient()) {
        self.lookup = lookup
    }

    func lookUp(_ rawUsername: String) async {
        let query = rawUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            state = .idle
            return
        }

        generation += 1
        let requestGeneration = generation
        confirmedCandidate = nil
        state = .lookingUp(query)

        do {
            let account = try await lookup.account(username: query)
            guard requestGeneration == generation, !Task.isCancelled else { return }
            state = .candidate(account)
        } catch is CancellationError {
            guard requestGeneration == generation else { return }
            state = .idle
        } catch {
            guard requestGeneration == generation, !Task.isCancelled else { return }
            state = .failed(
                query: query,
                message: error.localizedDescription
            )
        }
    }

    func confirmCandidate() {
        guard case .candidate(let account) = state else { return }
        confirmedCandidate = account
        state = .confirmed(account)
    }

    func invalidateCandidate() {
        generation += 1
        confirmedCandidate = nil
        if case .idle = state {
            return
        }
        state = .idle
    }
}
