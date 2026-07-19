import Foundation

public enum AnalysisJobReductionError: Error, Equatable {
    case nonMonotonicTransition
    case terminalStateIsImmutable
    case invalidProgress
    case completedJobRequiresReport
}

public enum AnalysisJobReducer {
    public static func advance(
        _ current: AnalysisJobSnapshot,
        to nextState: AnalysisJobState,
        at date: Date,
        progress: AnalysisProgress? = nil,
        terminalReason: AnalysisTerminalReason? = nil,
        reportID: ReportID? = nil
    ) throws -> AnalysisJobSnapshot {
        guard !current.state.isTerminal else {
            throw AnalysisJobReductionError.terminalStateIsImmutable
        }
        guard isAllowed(from: current.state, to: nextState) else {
            throw AnalysisJobReductionError.nonMonotonicTransition
        }
        if let progress,
            progress.completedPlies < 0
                || progress.totalPlies < 0
                || progress.completedPlies > progress.totalPlies
        {
            throw AnalysisJobReductionError.invalidProgress
        }
        if nextState == .completed, reportID == nil {
            throw AnalysisJobReductionError.completedJobRequiresReport
        }

        return AnalysisJobSnapshot(
            protocolVersion: current.protocolVersion,
            requestID: current.requestID,
            state: nextState,
            reception: reception(for: nextState, current: current.reception),
            progress: progress ?? current.progress,
            updatedAt: date,
            terminalReason: terminalReason,
            reportID: reportID
        )
    }

    private static func isAllowed(
        from current: AnalysisJobState,
        to next: AnalysisJobState
    ) -> Bool {
        if next == current {
            return true
        }
        if next.isTerminal {
            return true
        }
        guard let currentOrder = activeOrder[current],
            let nextOrder = activeOrder[next]
        else {
            return false
        }
        return nextOrder > currentOrder
    }

    private static func reception(
        for state: AnalysisJobState,
        current: RequestReception
    ) -> RequestReception {
        guard let order = activeOrder[state],
            let acceptedOrder = activeOrder[.accepted],
            order >= acceptedOrder
        else {
            return current
        }
        return .accepted
    }

    private static let activeOrder: [AnalysisJobState: Int] = [
        .submitted: 0,
        .queued: 1,
        .accepted: 2,
        .waitingForEngine: 3,
        .analyzing: 4,
        .packaging: 5,
        .transferring: 6,
        .completed: 7,
    ]
}

public enum AnalysisCancellationDisposition: Equatable, Sendable {
    case cancelled
    case tooLate
}

public enum AnalysisCancellationReducer {
    public static func apply(
        to snapshot: AnalysisJobSnapshot,
        at date: Date
    ) throws -> AnalysisCancellationDisposition {
        _ = date
        if snapshot.state == .completed {
            return .tooLate
        }
        if snapshot.state.isTerminal {
            return snapshot.state == .cancelled ? .cancelled : .tooLate
        }
        return .cancelled
    }
}
