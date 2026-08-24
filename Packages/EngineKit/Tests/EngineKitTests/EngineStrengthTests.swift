import Testing
@testable import EngineKit

@Suite struct EngineStrengthTests {
    @Test func presetsMapToExpectedSkillLevelsAndDepths() {
        #expect(EngineStrength.beginner.skillLevel == 0)
        #expect(EngineStrength.beginner.depth == 3)
        #expect(EngineStrength.beginner.movetimeCeilingMilliseconds == 500)
        #expect(EngineStrength.beginner.estimatedElo == 600)

        #expect(EngineStrength.casual.skillLevel == 4)
        #expect(EngineStrength.casual.depth == 5)
        #expect(EngineStrength.casual.movetimeCeilingMilliseconds == 750)
        #expect(EngineStrength.casual.estimatedElo == 1000)

        #expect(EngineStrength.intermediate.skillLevel == 9)
        #expect(EngineStrength.intermediate.depth == 8)
        #expect(EngineStrength.intermediate.movetimeCeilingMilliseconds == 1000)
        #expect(EngineStrength.intermediate.estimatedElo == 1400)

        #expect(EngineStrength.advanced.skillLevel == 14)
        #expect(EngineStrength.advanced.depth == 12)
        #expect(EngineStrength.advanced.movetimeCeilingMilliseconds == 1500)
        #expect(EngineStrength.advanced.estimatedElo == 1800)

        #expect(EngineStrength.master.skillLevel == 20)
        #expect(EngineStrength.master.depth == 18)
        #expect(EngineStrength.master.movetimeCeilingMilliseconds == 2500)
        #expect(EngineStrength.master.estimatedElo == 2400)
    }

    @Test func customStrengthClampsSkillLevelAndLimits() {
        let clampedBelow = EngineStrength(
            id: "custom-low",
            name: "Custom Low",
            skillLevel: -5,
            depth: 0,
            movetimeCeilingMilliseconds: 10
        )
        #expect(clampedBelow.skillLevel == 0)
        #expect(clampedBelow.depth == 1)
        #expect(clampedBelow.movetimeCeilingMilliseconds == 50)

        let clampedAbove = EngineStrength(
            id: "custom-high",
            name: "Custom High",
            skillLevel: 25,
            depth: 30,
            movetimeCeilingMilliseconds: 5000
        )
        #expect(clampedAbove.skillLevel == 20)
        #expect(clampedAbove.depth == 30)
        #expect(clampedAbove.movetimeCeilingMilliseconds == 5000)
    }

    @Test func allCasesContainsAllFivePresets() {
        #expect(EngineStrength.allCases.count == 5)
        #expect(EngineStrength.allCases.map(\.id) == ["beginner", "casual", "intermediate", "advanced", "master"])
    }
}
