import AnalysisKit
import ChessCore
import Foundation
import Testing

@testable import CoachKit

private enum TestFixtureError: Error { case missingResource }

private func loadFixtureInput() throws -> ReportInput {
    guard let url = Bundle.module.url(forResource: "real-fixture-game-report-input", withExtension: "json") else {
        throw TestFixtureError.missingResource
    }
    return try JSONDecoder().decode(ReportInput.self, from: Data(contentsOf: url))
}

struct CoachPayloadBuilderTests {
    @Test func momentPayloadMatchesTheCommittedGoldenJSON() throws {
        let input = try loadFixtureInput()
        let report = ReportBuilder.build(input: input, openingBook: OpeningBook.shared)
        #expect(report != nil)
        guard let report, let firstMoment = report.keyMoments.first else { return }

        let payload = CoachPayloadBuilder.momentPayload(firstMoment, input: input)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(payload)
        let rendered = String(data: data, encoding: .utf8)!

        guard let goldenURL = Bundle.module.url(forResource: "real-fixture-first-moment-golden-payload", withExtension: "json") else {
            Issue.record("missing golden payload fixture")
            return
        }
        let golden = try String(contentsOf: goldenURL, encoding: .utf8)
        #expect(rendered == golden.trimmingCharacters(in: .newlines))
    }

    @Test func summaryPayloadCarriesOneLinerPerKeyMoment() throws {
        let input = try loadFixtureInput()
        let report = ReportBuilder.build(input: input, openingBook: OpeningBook.shared)
        #expect(report != nil)
        guard let report else { return }
        let summary = CoachPayloadBuilder.summaryPayload(report)
        #expect(summary.momentOneLiners.count == report.keyMoments.count)
        #expect(summary.momentOneLiners.allSatisfy { !$0.isEmpty })
    }

    @Test func momentPayloadSerializedSizeIsSane() throws {
        let input = try loadFixtureInput()
        let report = ReportBuilder.build(input: input, openingBook: OpeningBook.shared)
        guard let report else { return }
        for moment in report.keyMoments {
            let payload = CoachPayloadBuilder.momentPayload(moment, input: input)
            let data = try JSONEncoder().encode(payload)
            let wordCount = String(data: data, encoding: .utf8)!.split(separator: " ").count
            #expect(wordCount < 2000)
        }
    }

    // MARK: - Rating register selection

    @Test func fixedRatingBandsResolveDirectly() {
        #expect(RatingRegister.resolve(ratingBand: "beginner", userRating: 2500) == .beginner)
        #expect(RatingRegister.resolve(ratingBand: "intermediate", userRating: 100) == .intermediate)
        #expect(RatingRegister.resolve(ratingBand: "advanced", userRating: nil) == .advanced)
    }

    @Test func adaptiveResolvesFromUserRatingBands() {
        #expect(RatingRegister.resolve(ratingBand: "adaptive", userRating: 900) == .beginner)
        #expect(RatingRegister.resolve(ratingBand: "adaptive", userRating: 1199) == .beginner)
        #expect(RatingRegister.resolve(ratingBand: "adaptive", userRating: 1200) == .intermediate)
        #expect(RatingRegister.resolve(ratingBand: "adaptive", userRating: 1800) == .intermediate)
        #expect(RatingRegister.resolve(ratingBand: "adaptive", userRating: 1801) == .advanced)
        #expect(RatingRegister.resolve(ratingBand: "adaptive", userRating: 2500) == .advanced)
    }

    @Test func adaptiveWithUnknownRatingDefaultsToIntermediate() {
        #expect(RatingRegister.resolve(ratingBand: "adaptive", userRating: nil) == .intermediate)
    }
}
