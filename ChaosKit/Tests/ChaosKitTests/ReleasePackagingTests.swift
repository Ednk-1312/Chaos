import CommonCrypto
import XCTest
@testable import ChaosKit

/// Release-engineering invariants: tag/version parsing, artifact naming, and
/// the packaging layout of a freshly built app bundle. Paths are derived from
/// the repository root so these run in any clean checkout; bundle-content
/// assertions skip (with an explicit message) when no release build exists.
final class ReleasePackagingTests: XCTestCase {

    // MARK: - Repository layout

    private var repoRoot: URL {
        // Tests run from ChaosKit/.build/...; repo root is two levels up from the package dir.
        let pkg = URL(fileURLWithPath: #filePath)          // .../Chaos/ChaosKit/Tests/ChaosKitTests/ReleasePackagingTests.swift
            .deletingLastPathComponent()                    // ChaosKitTests
            .deletingLastPathComponent()                    // Tests
            .deletingLastPathComponent()                    // ChaosKit
            .deletingLastPathComponent()                    // repo root
        return pkg
    }

    /// The release version this checkout is at, derived from the git tag via
    /// Tools/Release/version.sh — never hard-coded, so tests survive version bumps.
    private var currentRelease: (tag: String, marketing: String, build: String, label: String, full: String) {
        get throws {
            let script = repoRoot.appendingPathComponent("Tools/Release/version.sh")
            guard FileManager.default.fileExists(atPath: script.path) else {
                throw XCTSkip("version.sh not present (not a full checkout)")
            }
            let out = try run(script.path, ["--shell"])
            var env: [String: String] = [:]
            for line in out.split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1)
                env[String(parts[0])] = parts.count > 1
                    ? String(parts[1]).replacingOccurrences(of: "\\ ", with: " ")
                    : ""
            }
            let tag = try XCTUnwrap(env["TAG"], "version.sh emitted no TAG")
            let v = try XCTUnwrap(ReleaseVersion(tag: tag), "TAG does not parse: \(tag)")
            return (tag, v.marketing, v.build, v.label, v.full)
        }
    }

    // MARK: - Tag parsing (mirrors Tools/Release/version.sh)

    private struct ReleaseVersion: Equatable {
        let marketing: String
        let build: String
        let label: String
        let full: String

        init?(tag: String) {
            // Mirrors Tools/Release/version.sh: ^v([0-9]+)\.([0-9]+)\.([0-9]+)-preview\.([0-9]+)$
            guard tag.hasPrefix("v") else { return nil }
            let parts = tag.dropFirst().split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 2, parts[1].hasPrefix("preview.") else { return nil }
            let preview = parts[1].dropFirst("preview.".count)
            let nums = parts[0].split(separator: ".", omittingEmptySubsequences: false)
            func numeric(_ s: some StringProtocol) -> Bool { !s.isEmpty && s.allSatisfy(\.isNumber) }
            guard nums.count == 3, nums.allSatisfy(numeric), numeric(preview) else { return nil }
            marketing = nums.map(String.init).joined(separator: ".")
            build = String(preview)
            label = "Preview \(preview)"
            full = "\(marketing)-preview.\(build)"
        }
    }

    func testTagParsingMatchesVersionToolOutput() throws {
        let v = try XCTUnwrap(ReleaseVersion(tag: "v0.1.0-preview.1"))
        XCTAssertEqual(v.marketing, "0.1.0")
        XCTAssertEqual(v.build, "1")
        XCTAssertEqual(v.label, "Preview 1")
        XCTAssertEqual(v.full, "0.1.0-preview.1")

        // Reject malformed tags the same way the shell tool does.
        XCTAssertNil(ReleaseVersion(tag: "v1.0"))
        XCTAssertNil(ReleaseVersion(tag: "v1.0.0"))
        XCTAssertNil(ReleaseVersion(tag: "0.1.0-preview.1"))
        XCTAssertNil(ReleaseVersion(tag: "v1.0.0-beta.1"))
        XCTAssertNil(ReleaseVersion(tag: "v1.0.0-preview.x"))
        XCTAssertNil(ReleaseVersion(tag: "v1.0-preview.1"))
        XCTAssertNil(ReleaseVersion(tag: "v1.0.0.-preview.1"))
    }

    // MARK: - Artifact naming convention

    func testArtifactNamesFollowConvention() {
        let tag = "v0.1.0-preview.1"
        let base = "Chaos-v\(tag.dropFirst())"
        XCTAssertEqual(base, "Chaos-v0.1.0-preview.1")
        XCTAssertEqual("\(base).pkg", "Chaos-v0.1.0-preview.1.pkg")
        XCTAssertEqual("\(base).zip", "Chaos-v0.1.0-preview.1.zip")

        // Filenames must not embed timestamps, UUIDs, or machine-specific data.
        let forbidden = [" ", "/", ":", "~", "tmp", "Users"]
        for f in forbidden {
            XCTAssertFalse(base.contains(f), "artifact name must not contain \(f)")
        }
    }

    // MARK: - Version tool agreement (when git metadata is present)

    func testVersionShellOutputAgreesWithXcconfig() throws {
        let script = repoRoot.appendingPathComponent("Tools/Release/version.sh")
        guard FileManager.default.fileExists(atPath: script.path) else {
            throw XCTSkip("version.sh not present (not a full checkout)")
        }
        let r = try currentRelease
        let out = try run(script.path, ["--shell"])
        let env = Dictionary(uniqueKeysWithValues: out.split(separator: "\n").map { line -> (String, String) in
            let parts = line.split(separator: "=", maxSplits: 1)
            // version.sh emits %q-quoted values; undo the shell escaping here.
            let raw = parts.count > 1 ? String(parts[1]) : ""
            return (String(parts[0]), raw.replacingOccurrences(of: "\\ ", with: " "))
        })
        XCTAssertEqual(env["TAG"], r.tag)
        XCTAssertEqual(env["MARKETING_VERSION"], r.marketing)
        XCTAssertEqual(env["CURRENT_PROJECT_VERSION"], r.build)
        XCTAssertEqual(env["RELEASE_LABEL"], r.label)
        XCTAssertEqual(env["FULL_VERSION"], r.full)

        // Version.xcconfig must carry the same marketing/build versions.
        let xc = try String(contentsOf: repoRoot.appendingPathComponent("Version.xcconfig"), encoding: .utf8)
        XCTAssertTrue(xc.contains("MARKETING_VERSION = \(r.marketing)"), "Version.xcconfig marketing version drifted")
        XCTAssertTrue(xc.contains("CURRENT_PROJECT_VERSION = \(r.build)"), "Version.xcconfig build version drifted")
    }

    func testVersionShellValuesSurviveShellRoundtrip() throws {
        // Regression: RELEASE_LABEL contains a space; the emitted KEY=VALUE lines
        // must round-trip through `eval` without word-splitting.
        let script = repoRoot.appendingPathComponent("Tools/Release/version.sh")
        guard FileManager.default.fileExists(atPath: script.path) else {
            throw XCTSkip("version.sh not present (not a full checkout)")
        }
        let r = try currentRelease
        let out = try run("/bin/bash", ["-c",
            "out=\"$(\"\(script.path)\" --shell)\" && eval \"$out\" && printf '%s' \"$RELEASE_LABEL\""])
        XCTAssertEqual(out, r.label)
    }

    // MARK: - Built bundle contents (skips cleanly when no release build exists)

    private var releaseApp: URL { repoRoot.appendingPathComponent("build/release/Chaos.app") }
    private var ciApp: URL { repoRoot.appendingPathComponent("build/ci/Chaos.app") }

    private var builtApp: URL? {
        [releaseApp, ciApp].first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func testBuiltAppBundleLayout() throws {
        guard let app = builtApp else {
            throw XCTSkip("no Chaos.app under build/ — run Tools/Release/build-release.sh to exercise this")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/MacOS/Chaos").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/MacOS/chaos-stress").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Helpers/chaos").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Info.plist").path))

        let plist = try XCTUnwrap(NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")))
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.chaosengineering.Chaos")

        if app == releaseApp { // release pipeline pins the version from the tag
            let r = try currentRelease
            XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, r.marketing)
            XCTAssertEqual(plist["CFBundleVersion"] as? String, r.build)
        }
    }

    func testReleaseArtifactsAndChecksumsAgree() throws {
        let dir = repoRoot.appendingPathComponent("build/release")
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("SHA256SUMS").path) else {
            throw XCTSkip("no release artifacts — run Tools/Release/build-release.sh to exercise this")
        }
        let r = try currentRelease
        for name in ["Chaos-v\(r.full).pkg", "Chaos-v\(r.full).zip", "SHA256SUMS"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path),
                          "missing artifact: \(name)")
        }
        // Checksums must actually match the artifacts.
        let sums = try String(contentsOf: dir.appendingPathComponent("SHA256SUMS"), encoding: .utf8)
        for line in sums.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            XCTAssertEqual(parts.count, 2, "malformed SHA256SUMS line: \(line)")
            let file = parts[1].trimmingCharacters(in: .whitespaces)
            let data = try Data(contentsOf: dir.appendingPathComponent(file))
            let digest = Self.sha256(data)
            XCTAssertEqual(digest, String(parts[0]), "checksum mismatch for \(file)")
        }
    }

    // MARK: - Manifest (when present)

    func testReleaseManifestShape() throws {
        let manifestURL = repoRoot.appendingPathComponent("build/release/release-manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw XCTSkip("no release manifest — run Tools/Release/build-release.sh to exercise this")
        }
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try XCTUnwrap(try JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        let r = try currentRelease
        XCTAssertEqual(manifest["tag"] as? String, r.tag)
        XCTAssertEqual(manifest["version"] as? String, r.full)
        XCTAssertEqual(manifest["marketingVersion"] as? String, r.marketing)
        XCTAssertEqual(manifest["architecture"] as? String, "arm64")
        let artifacts = try XCTUnwrap(manifest["artifacts"] as? [String: Any])
        XCTAssertEqual(artifacts.count, 2, "expected pkg + zip entries")
        for case let entry as [String: Any] in artifacts.values {
            XCTAssertNotNil(entry["name"] as? String)
            XCTAssertNotNil(entry["sha256"] as? String)
        }
        XCTAssertNotNil(manifest["signing"])
        XCTAssertNotNil(manifest["notarization"])
        // Machine-specific data must never leak into the manifest.
        let encoded = try JSONSerialization.data(withJSONObject: manifest)
        let text = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(text.contains("/Users/"), "manifest must not embed home paths")
    }

    // MARK: - Helpers

    private static func sha256(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buf in
            _ = CC_SHA256(buf.baseAddress, CC_LONG(buf.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    private func run(_ launchPath: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        p.currentDirectoryURL = repoRoot
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "release", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: String(decoding: data, as: UTF8.self)])
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
