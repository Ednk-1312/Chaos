import Foundation

/// Local-first persistence. Everything lives under ~/Library/Application Support/Chaos.
public final class PersistenceStore: @unchecked Sendable {
    public static let shared = PersistenceStore()

    private let queue = DispatchQueue(label: "com.chaosengineering.persistence", qos: .utility)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()

    public let rootURL: URL
    public var recordsURL: URL { rootURL.appendingPathComponent("Records", isDirectory: true) }
    public var scenariosURL: URL { rootURL.appendingPathComponent("Scenarios", isDirectory: true) }
    public var suitesURL: URL { rootURL.appendingPathComponent("Suites", isDirectory: true) }
    public var suiteRunsURL: URL { rootURL.appendingPathComponent("SuiteRuns", isDirectory: true) }
    public var recipesURL: URL { rootURL.appendingPathComponent("Recipes", isDirectory: true) }
    public var profilesURL: URL { rootURL.appendingPathComponent("Profiles", isDirectory: true) }

    public init(rootURL: URL? = nil) {
        let base = rootURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Chaos", isDirectory: true)
        self.rootURL = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: base.appendingPathComponent("Records", isDirectory: true), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: base.appendingPathComponent("Scenarios", isDirectory: true), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: base.appendingPathComponent("Suites", isDirectory: true), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: base.appendingPathComponent("SuiteRuns", isDirectory: true), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: base.appendingPathComponent("Recipes", isDirectory: true), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: base.appendingPathComponent("Profiles", isDirectory: true), withIntermediateDirectories: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: Records

    public func save(record: ExperimentRecord) {
        lock.lock(); defer { lock.unlock() }
        queue.sync {
            let url = recordsURL.appendingPathComponent("\(record.id.uuidString).json")
            if let data = try? encoder.encode(record) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    public func loadRecords() -> [ExperimentRecord] {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: recordsURL, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(ExperimentRecord.self, from: data)
        }.sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
    }

    public func deleteRecord(id: UUID) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: recordsURL.appendingPathComponent("\(id.uuidString).json"))
    }

    // MARK: User Scenarios

    public func save(scenario: Scenario) {
        lock.lock(); defer { lock.unlock() }
        queue.sync {
            let url = scenariosURL.appendingPathComponent("\(scenario.id).json")
            if let data = try? encoder.encode(scenario) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    public func loadUserScenarios() -> [Scenario] {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: scenariosURL, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(Scenario.self, from: data)
        }
    }

    public func deleteScenario(id: String) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: scenariosURL.appendingPathComponent("\(id).json"))
    }

    // MARK: Recipes (saved bug recipes)

    public func save(recipe: Recipe) {
        lock.lock(); defer { lock.unlock() }
        queue.sync {
            if let data = try? encoder.encode(recipe) {
                try? data.write(to: recipesURL.appendingPathComponent("\(recipe.id).json"), options: .atomic)
            }
        }
    }

    public func loadRecipes() -> [Recipe] {
        lock.lock(); defer { lock.unlock() }
        return decodeAll(from: recipesURL)
    }

    public func deleteRecipe(id: String) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: recipesURL.appendingPathComponent("\(id).json"))
    }

    // MARK: Suites

    public func save(suite: ChaosSuite) {
        lock.lock(); defer { lock.unlock() }
        queue.sync {
            if let data = try? encoder.encode(suite) {
                try? data.write(to: suitesURL.appendingPathComponent("\(suite.id.uuidString).json"), options: .atomic)
            }
        }
    }

    public func loadSuites() -> [ChaosSuite] {
        lock.lock(); defer { lock.unlock() }
        return decodeAll(from: suitesURL).sorted { $0.createdAt > $1.createdAt }
    }

    public func deleteSuite(id: UUID) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: suitesURL.appendingPathComponent("\(id.uuidString).json"))
    }

    // MARK: Suite Runs

    public func save(suiteRun: SuiteRun) {
        lock.lock(); defer { lock.unlock() }
        queue.sync {
            if let data = try? encoder.encode(suiteRun) {
                try? data.write(to: suiteRunsURL.appendingPathComponent("\(suiteRun.id.uuidString).json"), options: .atomic)
            }
        }
    }

    public func loadSuiteRuns() -> [SuiteRun] {
        lock.lock(); defer { lock.unlock() }
        return decodeAll(from: suiteRunsURL).sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
    }

    // MARK: App Profiles

    public func save(profile: AppProfile) {
        lock.lock(); defer { lock.unlock() }
        queue.sync {
            if let data = try? encoder.encode(profile) {
                try? data.write(to: profilesURL.appendingPathComponent("\(profile.id.uuidString).json"), options: .atomic)
            }
        }
    }

    public func loadProfiles() -> [AppProfile] {
        lock.lock(); defer { lock.unlock() }
        return decodeAll(from: profilesURL).sorted { $0.createdAt < $1.createdAt }
    }

    public func deleteProfile(id: UUID) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: profilesURL.appendingPathComponent("\(id.uuidString).json"))
    }

    // MARK: Helpers

    private func decodeAll<T: Decodable>(from dir: URL) -> [T] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(T.self, from: data)
        }
    }
}
