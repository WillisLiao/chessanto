import Foundation
import Testing
@testable import CompanionDomain

@Suite("Analysis job reducer")
struct AnalysisJobReducerTests {
    @Test("job states advance monotonically")
    func jobStatesAdvanceMonotonically() throws {
        let submitted = AnalysisJobSnapshot(
            protocolVersion: .v1,
            requestID: AnalysisRequestID("request-1"),
            state: .submitted,
            reception: .submitted,
            progress: nil,
            updatedAt: Date(timeIntervalSince1970: 100),
            terminalReason: nil,
            reportID: nil
        )

        let accepted = try AnalysisJobReducer.advance(
            submitted,
            to: .accepted,
            at: Date(timeIntervalSince1970: 101)
        )

        #expect(accepted.state == .accepted)
        #expect(accepted.reception == .accepted)
        #expect(throws: AnalysisJobReductionError.nonMonotonicTransition) {
            try AnalysisJobReducer.advance(
                accepted,
                to: .queued,
                at: Date(timeIntervalSince1970: 102)
            )
        }
    }

    @Test("terminal job states are immutable")
    func terminalJobStatesAreImmutable() {
        let completed = AnalysisJobSnapshot(
            protocolVersion: .v1,
            requestID: AnalysisRequestID("request-1"),
            state: .completed,
            reception: .accepted,
            progress: AnalysisProgress(completedPlies: 42, totalPlies: 42),
            updatedAt: Date(timeIntervalSince1970: 200),
            terminalReason: nil,
            reportID: ReportID("report-1")
        )

        #expect(throws: AnalysisJobReductionError.terminalStateIsImmutable) {
            try AnalysisJobReducer.advance(
                completed,
                to: .failed,
                at: Date(timeIntervalSince1970: 201),
                terminalReason: .engineUnavailable
            )
        }
    }

    @Test("cancellation distinguishes cancelled work from a completed job")
    func cancellationDistinguishesCancelledWorkFromACompletedJob() throws {
        let queued = AnalysisJobSnapshot(
            protocolVersion: .v1,
            requestID: AnalysisRequestID("request-1"),
            state: .queued,
            reception: .submitted,
            progress: nil,
            updatedAt: Date(timeIntervalSince1970: 100),
            terminalReason: nil,
            reportID: nil
        )
        let completed = AnalysisJobSnapshot(
            protocolVersion: .v1,
            requestID: AnalysisRequestID("request-2"),
            state: .completed,
            reception: .accepted,
            progress: AnalysisProgress(completedPlies: 42, totalPlies: 42),
            updatedAt: Date(timeIntervalSince1970: 200),
            terminalReason: nil,
            reportID: ReportID("report-1")
        )

        let cancelled = try AnalysisCancellationReducer.apply(
            to: queued,
            at: Date(timeIntervalSince1970: 101)
        )
        let tooLate = try AnalysisCancellationReducer.apply(
            to: completed,
            at: Date(timeIntervalSince1970: 201)
        )

        #expect(cancelled == .cancelled)
        #expect(tooLate == .tooLate)
    }
}
