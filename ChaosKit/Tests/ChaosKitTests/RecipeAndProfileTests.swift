import XCTest
@testable import ChaosKit

// MARK: - Recipe round-trip: save from a record, replay via makeConfig

final class RecipeRoundTripTests: XCTestCase {
    var store: PersistenceStore!

    override func setUp() {
        super.setUp()
        store = PersistenceStore(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("chaos-recipe-\(UUID().uuidString)", isDirectory: true)
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: store.rootURL)
        store = nil
        super.tearDown()
    }

    /// A realistic failed record: multiple faults across categories, a target,
    /// assertions with mixed outcomes, a seed, and restoration state.
    private func makeFailedRecord() -> ExperimentRecord {
        let target = TargetDescriptor(kind: .process, name: "Backend", bundleID: "com.example.backend")
        let assertions = [
            Assertion(kind: .processAlive, subject: "4242"),
            Assertion(kind: .endpointReachable, subject: "api.backend.internal:443"),
            Assertion(kind: .logContains, subject: "com.example.backend"),
        ]
        var config = ExperimentConfig(
            name: "Server Outage Repro",
            seed: 0xDEADBEEFCAFE,
            plannedDuration: 330,
            bindings: [
                FaultBinding(faultID: .dependencyDown, startOffset: 30, duration: 300,
                             parameters: ["port": "443"]),
                FaultBinding(faultID: .packetLoss, startOffset: 0, duration: 120,
                             parameters: ["lossPercent": "10"]),
            ],
            targets: [target],
            assertions: assertions,
            notes: "checkout 500s when dependency goes dark",
            safetyConfirmed: true
        )
        config.safetyConfirmed = true
        var record = ExperimentRecord(
            config: config,
            outcome: .failed,
            startedAt: Date(timeIntervalSince1970: 1_760_000_000),
            endedAt: Date(timeIntervalSince1970: 1_760_000_315)
        )
        record.assertionResults = [
            assertions[0].id: .passed,
            assertions[1].id: .failed,
            assertions[2].id: .inconclusive,
        ]
        return record
    }

    private func makeRecipe(from record: ExperimentRecord, purpose: String = "checkout 500s under outage") -> Recipe {
        var recipe = Recipe(reproducing: record, purpose: purpose)
        recipe.id = "fixed-recipe-id" // deterministic file name for the store round-trip
        return recipe
    }

    func testSaveFromRecordCapturesReproducibilityIdentity() {
        let record = makeFailedRecord()
        let recipe = makeRecipe(from: record)

        XCTAssertEqual(recipe.name, record.config.name)
        XCTAssertEqual(recipe.purpose, "checkout 500s under outage")
        XCTAssertEqual(recipe.seed, record.config.seed)
        XCTAssertEqual(recipe.targets, record.config.targets)
        XCTAssertEqual(recipe.assertions, record.config.assertions)
        XCTAssertEqual(recipe.sourceExperimentID, record.id)
        XCTAssertEqual(recipe.targetName, "Backend")
        XCTAssertEqual(recipe.scenario.bindings, record.config.bindings)
        XCTAssertEqual(recipe.scenario.category, "Recipes")
    }

    func testSaveFromRecordWithEmptyPurposeUsesHonestFallback() {
        let recipe = makeRecipe(from: makeFailedRecord(), purpose: "")
        XCTAssertEqual(recipe.scenario.summary, "Saved from an experiment")
    }

    func testMakeConfigReproducesTheRecordedFailureCondition() {
        let record = makeFailedRecord()
        let config = makeRecipe(from: record).makeConfig()

        XCTAssertEqual(config.name, record.config.name)
        XCTAssertEqual(config.seed, record.config.seed, "replay must reuse the captured seed")
        XCTAssertEqual(config.bindings, record.config.bindings)
        XCTAssertEqual(config.targets, record.config.targets)
        XCTAssertEqual(config.assertions, record.config.assertions)
        XCTAssertEqual(config.notes, "checkout 500s under outage")
        XCTAssertTrue(config.safetyConfirmed, "makeConfig defaults to safety-confirmed for the confirmation sheet")
        XCTAssertEqual(
            config.plannedDuration,
            record.config.bindings.map { $0.startOffset + $0.duration }.max(),
            "planned duration covers the longest fault window"
        )
    }

    func testMakeConfigSeedOverrideWins() {
        let recipe = makeRecipe(from: makeFailedRecord())
        let config = recipe.makeConfig(seed: 7)
        XCTAssertEqual(config.seed, 7)
    }

    func testRecipePersistsAndRestoresThroughStore() {
        let record = makeFailedRecord()
        let recipe = makeRecipe(from: record)

        store.save(recipe: recipe)
        let loaded = store.loadRecipes()

        XCTAssertEqual(loaded.count, 1)
        let restored = try! XCTUnwrap(loaded.first)
        XCTAssertEqual(restored.id, "fixed-recipe-id")
        XCTAssertEqual(restored.seed, recipe.seed)
        XCTAssertEqual(restored.targets, recipe.targets)
        XCTAssertEqual(restored.assertions, recipe.assertions)
        XCTAssertEqual(restored.sourceExperimentID, recipe.sourceExperimentID)
        XCTAssertEqual(restored.scenario, recipe.scenario)
        XCTAssertEqual(restored.purpose, recipe.purpose)
    }

    func testLegacyRecipeWithoutCapturedFieldsDecodesWithDefaults() {
        // A recipe saved before seed/targets/assertions existed must still load.
        let legacyJSON = """
        {
          "id": "legacy-1",
          "name": "Old Recipe",
          "purpose": "repro from before capture fields",
          "scenario": {
            "id": "legacy-scenario",
            "name": "Old Recipe",
            "summary": "s",
            "category": "Recipes",
            "symbolName": "checklist",
            "isBuiltin": false,
            "isExtreme": false,
            "bindings": [
              {"id": "11111111-2222-3333-4444-555555555555", "faultID": "network.latency",
               "name": "Latency", "parameters": {}, "startOffset": 0, "duration": 60,
               "severity": "moderate", "enabled": true}
            ]
          }
        }
        """
        let url = store.recipesURL.appendingPathComponent("legacy-1.json")
        try! legacyJSON.data(using: .utf8)!.write(to: url)

        let loaded = store.loadRecipes()
        let legacy = try! XCTUnwrap(loaded.first)
        XCTAssertNil(legacy.seed, "legacy recipes have no captured seed")
        XCTAssertTrue(legacy.targets.isEmpty)
        XCTAssertTrue(legacy.assertions.isEmpty)
        XCTAssertNil(legacy.sourceExperimentID)

        // makeConfig must still produce a runnable plan without a captured seed.
        let config = legacy.makeConfig()
        XCTAssertEqual(config.bindings.count, 1)
        XCTAssertEqual(config.bindings.first?.faultID, .networkLatency)
        XCTAssertNotNil(config.seed, "a fresh seed is generated when none was captured")
    }

    func testReplayPlanAndRecipeConfigsAgree() {
        // ReplayPlan (exact replay) and Recipe.makeConfig (bug recipe replay)
        // must encode the same failure condition for the same record.
        let record = makeFailedRecord()
        let planConfig = ReplayPlan(config: record.config).makeConfig()
        let recipeConfig = makeRecipe(from: record).makeConfig()

        XCTAssertEqual(planConfig.seed, recipeConfig.seed)
        XCTAssertEqual(planConfig.bindings, recipeConfig.bindings)
        XCTAssertEqual(planConfig.targets, recipeConfig.targets)
        XCTAssertEqual(planConfig.assertions, recipeConfig.assertions)
    }
}

// MARK: - Profile recommendation honesty rules

final class ProfileRecommendationHonestyTests: XCTestCase {

    func testNoDependenciesMeansNoDependencyScenarioRecommended() {
        let profile = AppProfile(name: "Solo App", configuredDependencies: [])
        let recommended = profile.recommendedScenarios

        XCTAssertFalse(recommended.isEmpty, "baseline recommendations still exist")
        XCTAssertFalse(
            recommended.contains { $0.id == "server-outage" },
            "no dependency declared → no dependency scenario"
        )
        XCTAssertFalse(
            recommended.contains { $0.bindings.contains { $0.faultID.category == .dependency } },
            "no dependency-category faults may be recommended without a declared dependency"
        )
    }

    func testDeclaredDependencyAddsServerOutage() {
        let profile = AppProfile(name: "Client App", configuredDependencies: ["api.backend.internal:443"])
        let recommended = profile.recommendedScenarios

        XCTAssertTrue(recommended.contains { $0.id == "server-outage" })
    }

    func testExplicitRecommendationsAreUsedVerbatimWhenPresent() {
        // If the user pinned scenario IDs, those are used exactly — the
        // fallback must not append anything.
        let profile = AppProfile(
            name: "Pinned",
            configuredDependencies: ["api:443"],
            recommendedScenarioIDs: ["terrible-wifi"]
        )
        let recommended = profile.recommendedScenarios
        XCTAssertEqual(recommended.map(\.id), ["terrible-wifi"], "explicit list is used verbatim")
    }

    func testUnknownScenarioIDsAreDroppedNotInvented() {
        // IDs that don't resolve in the library are silently dropped; only
        // real, runnable scenarios come out.
        let profile = AppProfile(
            name: "Typo",
            recommendedScenarioIDs: ["does-not-exist", "terrible-wifi"]
        )
        let recommended = profile.recommendedScenarios
        XCTAssertEqual(recommended.map(\.id), ["terrible-wifi"])
        XCTAssertTrue(recommended.allSatisfy { ScenarioLibrary.scenario(id: $0.id) != nil })
    }

    func testEmptyIDFallbackStaysBaselineAndHonest() {
        // Empty explicit IDs → fallback list. The fallback must never include
        // dependency faults, regardless of declared dependencies being absent.
        var profile = AppProfile(name: "Fallback")
        profile.recommendedScenarioIDs = []
        let recommended = profile.recommendedScenarios

        XCTAssertFalse(recommended.isEmpty)
        XCTAssertFalse(recommended.contains { $0.id == "server-outage" && profile.configuredDependencies.isEmpty })
        XCTAssertTrue(recommended.contains { $0.id == "terrible-wifi" })
        XCTAssertTrue(recommended.contains { $0.id == "memory-moderate" })
    }

    func testMatchingRecordsUsesIdentityNotGuesses() {
        // A profile matches only records whose target bundle id / name or
        // record name matches — never inferred metadata.
        var config = ExperimentConfig(
            name: "Backend Torture",
            plannedDuration: 60,
            bindings: [FaultBinding(faultID: .cpuLoad, startOffset: 0, duration: 30)]
        )
        config.safetyConfirmed = true
        let matchedTarget = ExperimentRecord(
            config: { var c = config; c.targets = [TargetDescriptor(kind: .process, name: "Backend", bundleID: "com.example.backend")]; return c }(),
            outcome: .passed
        )
        let matchedName = ExperimentRecord(config: config, outcome: .passed) // record name == profile name path
        let profile = AppProfile(name: "Backend Torture", bundleID: "com.example.backend")
        let matches = profile.matchingRecords(in: [matchedTarget, matchedName])
        XCTAssertEqual(matches.count, 2, "bundle-ID match and record-name match both count")
    }

    func testMatchingRecordsExcludesUnrelatedRuns() {
        var config = ExperimentConfig(
            name: "Unrelated",
            plannedDuration: 60,
            bindings: [FaultBinding(faultID: .memoryPressure, startOffset: 0, duration: 30)]
        )
        config.safetyConfirmed = true
        let unrelated = ExperimentRecord(config: config, outcome: .passed)

        let profile = AppProfile(name: "Backend Torture", bundleID: "com.example.backend")
        XCTAssertTrue(profile.matchingRecords(in: [unrelated]).isEmpty)
    }

    func testEveryRecommendedScenarioIsRunnableFromTheLibrary() {
        // Across any combination of declarations, recommendations must always
        // resolve to real library scenarios (never invented ones).
        let profiles = [
            AppProfile(name: "A", configuredDependencies: []),
            AppProfile(name: "B", configuredDependencies: ["x:1"]),
            AppProfile(name: "C", configuredDependencies: ["x:1", "y:2"]),
            AppProfile(name: "D", recommendedScenarioIDs: ["worst-day"]),
            AppProfile(name: "E", recommendedScenarioIDs: ["nope", "critical-disk"]),
        ]
        for profile in profiles {
            let recommended = profile.recommendedScenarios
            XCTAssertEqual(
                recommended.count,
                Set(recommended.map(\.id)).count,
                "no duplicate recommendations"
            )
            for scenario in recommended {
                XCTAssertNotNil(ScenarioLibrary.scenario(id: scenario.id))
                XCTAssertFalse(scenario.bindings.isEmpty, "recommended scenarios must carry a runnable plan")
            }
        }
    }

    func testDependencyRecommendationOnlyAppearsWhenDependencyDeclared() {
        // The exact honesty invariant: server-outage iff a dependency exists.
        let without = AppProfile(name: "No Deps", configuredDependencies: [])
        let with = AppProfile(name: "With Deps", configuredDependencies: ["db.internal:5432"])

        XCTAssertFalse(without.recommendedScenarios.contains { $0.id == "server-outage" })
        XCTAssertTrue(with.recommendedScenarios.contains { $0.id == "server-outage" })
    }
}
