import Foundation

/// Storage + filesystem faults. Every write-path fault operates inside Chaos-managed
/// sandbox directories or user-approved folders; the real disk is never filled.
public enum ChaosSandbox {
    public static var rootURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Chaos", isDirectory: true)
        return base.appendingPathComponent("Sandbox", isDirectory: true)
    }

    public static func makeExperimentDirectory() -> URL {
        let url = rootURL.appendingPathComponent("exp-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func purgeAll() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

final class StorageFilesystemFaultRunner: FaultRunner {
    let id: FaultID
    private let vault = ChaosSandbox.rootURL.appendingPathComponent("Vault", isDirectory: true)
    private static var lockHolderPIDs: [pid_t] = []

    init(id: FaultID) { self.id = id }

    func activate(_ context: FaultContext) async -> ActivationResult {
        switch id {
        case .storageFill:
            return await activateStorageFill(context)
        case .fsMissingFile:
            return await activateMissingFile(context)
        case .fsReadOnly:
            return await activateReadOnly(context)
        case .fsPermissionDenied, .permissionDenied:
            return await activatePermissionDenied(context)
        case .fsLocked:
            return await activateLocked(context)
        case .fsDelayedAvailability:
            return await activateDelayed(context)
        default:
            return .failure("StorageFilesystemFaultRunner cannot execute \(id.rawValue).")
        }
    }

    // MARK: Storage Fill

    private func activateStorageFill(_ context: FaultContext) async -> ActivationResult {
        let gb = max(1, context.intParam("capacityGB", default: 1))
        let freeGB = max(1, context.intParam("freeGB", default: 1))
        let imageDir = ChaosSandbox.rootURL.appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)
        let imagePath = imageDir.appendingPathComponent("chaos-disk-\(Int.random(in: 1000...9999)).dmg").path

        // Sparse image: capacity GB total, we then fill it until only freeGB remains.
        let create = (try? Shell.run("/usr/bin/hdiutil", [
            "create", "-size", "\(gb)g", "-type", "SPARSE", "-fs", "APFS",
            "-volname", "ChaosTest", imagePath
        ])) ?? ShellResult(exitCode: 1, stdout: "", stderr: "launch failed")

        guard create.succeeded else {
            return .failure("hdiutil failed: \(create.combinedOutput.prefix(160))")
        }

        let attach = (try? Shell.run("/usr/bin/hdiutil", ["attach", imagePath, "-nobrowse"]))
            ?? ShellResult(exitCode: 1, stdout: "", stderr: "")
        guard attach.succeeded else {
            try? FileManager.default.removeItem(atPath: imagePath)
            return .failure("Could not attach test volume.")
        }

        // Extract the mount point from hdiutil output.
        let mountPoint = attach.stdout
            .split(separator: "\n")
            .last.map { $0.split(separator: "\t").last.map(String.init) ?? "" } ?? ""
        guard !mountPoint.isEmpty, FileManager.default.fileExists(atPath: mountPoint) else {
            _ = (try? Shell.run("/usr/bin/hdiutil", ["detach", mountPoint, "-force"]))
            return .failure("Volume mounted but mount point not found.")
        }

        // Fill until freeGB remain. Write in 64 MB chunks of real data.
        let chunkBytes = 64 * 1024 * 1024
        let buffer = Data(repeating: 0x43, count: chunkBytes) // 'C'
        var written: UInt64 = 0
        let targetBytes = UInt64(gb - freeGB) * 1_000_000_000
        let fillURL = URL(fileURLWithPath: mountPoint).appendingPathComponent("chaos.fill")

        FileManager.default.createFile(atPath: fillURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: fillURL) else {
            return .failure("Could not create fill file on test volume.")
        }
        while written < targetBytes {
            do {
                try handle.write(contentsOf: buffer)
                written += UInt64(chunkBytes)
            } catch {
                break // volume effectively full at the desired threshold or earlier
            }
        }
        try? handle.close()

        let mount = mountPoint
        context.emit(ExperimentEvent(
            kind: .info,
            message: "Test volume at \(mount): \(ByteCount.string(written)) written, ~\(freeGB) GB left free."
        ))
        return .success("Disk near-full simulation active on \(mount) (image: \(imagePath)).")
    }

    // MARK: Missing File

    private func activateMissingFile(_ context: FaultContext) async -> ActivationResult {
        guard let dir = approvedDirectory(context) else {
            return .failure("No directory target. This fault only runs inside Chaos sandbox or user-approved folders.")
        }
        try? FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else {
            return .failure("Could not read directory \(dir.path).")
        }
        var moved = 0
        for case let url as URL in enumerator {
            if url.path.contains("/.ChaosVault/") { continue }
            if fm.isReadableFile(atPath: url.path) {
                let dest = vault.appendingPathComponent(UUID().uuidString)
                if (try? fm.moveItem(at: url, to: dest)) != nil { moved += 1 }
                if moved >= 50 { break }
            }
        }
        // Write a manifest so restore can put files back.
        let manifest = vault.appendingPathComponent("manifest-\(context.binding.id.uuidString).txt")
        try? dir.path.write(to: manifest, atomically: true, encoding: .utf8)
        return .success("Moved \(moved) item(s) from \(dir.lastPathComponent) into the Chaos vault.")
    }

    // MARK: Read-only

    private func activateReadOnly(_ context: FaultContext) async -> ActivationResult {
        guard let dir = approvedDirectory(context) else {
            return .failure("No directory target for read-only fault.")
        }
        let fm = FileManager.default
        var count = 0
        if let paths = try? fm.subpathsOfDirectory(atPath: dir.path) {
            for p in paths.prefix(200) {
                let full = dir.appendingPathComponent(p).path
                var attrs = try? fm.attributesOfItem(atPath: full)
                attrs?[.posixPermissions] = 0o444
                if (try? fm.setAttributes(attrs ?? [:], ofItemAtPath: full)) != nil { count += 1 }
            }
        }
        saveModeSnapshot(dir: dir, context: context)
        return .success("Set \(count) item(s) read-only in \(dir.lastPathComponent).")
    }

    // MARK: Permission denied

    private func activatePermissionDenied(_ context: FaultContext) async -> ActivationResult {
        guard let dir = approvedDirectory(context) else {
            return .failure("No directory target for permission fault.")
        }
        saveModeSnapshot(dir: dir, context: context)
        let fm = FileManager.default
        var count = 0
        if let paths = try? fm.subpathsOfDirectory(atPath: dir.path) {
            for p in paths.prefix(200) {
                let full = dir.appendingPathComponent(p).path
                var attrs = try? fm.attributesOfItem(atPath: full)
                attrs?[.posixPermissions] = 0o000
                if (try? fm.setAttributes(attrs ?? [:], ofItemAtPath: full)) != nil { count += 1 }
            }
        }
        return .success("POSIX permissions revoked (000) on \(count) item(s) in \(dir.lastPathComponent).")
    }

    // MARK: Locked files

    private func activateLocked(_ context: FaultContext) async -> ActivationResult {
        guard let dir = approvedDirectory(context) else {
            return .failure("No directory target for lock contention.")
        }
        // Open files with flock via /usr/bin/flock helper is unavailable on macOS;
        // emulate by holding open file descriptors in a long-running child (sh + sleep).
        let script = """
        for f in "\(dir.path)"/*; do
          [ -e "$f" ] || continue
          while :; do sleep 3600 & wait $!; done &
          exec 3>"$f"
        done
        sleep 999999
        """
        let proc = Foundation.Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", script]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            Self.lockHolderPIDs.append(proc.processIdentifier)
        } catch { return .failure("Could not start lock holder.") }
        return .success("Lock holder running (pid \(proc.processIdentifier)).")
    }

    // MARK: Delayed availability

    private func activateDelayed(_ context: FaultContext) async -> ActivationResult {
        let dir = ChaosSandbox.makeExperimentDirectory()
        let delay = context.intParam("delaySeconds", default: 5)
        let fileName = context.param("fileName", default: "config.json")
        let hidden = dir.appendingPathComponent(".pending-\(fileName)")
        let final = dir.appendingPathComponent(fileName)
        try? "{\"chaos\": \"delayed fixture\", \"createdAt\": \"\(Date())\"}".write(to: hidden, atomically: true, encoding: .utf8)

        let task = DispatchWorkItem {
            try? FileManager.default.moveItem(at: hidden, to: final)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + TimeInterval(delay), execute: task)
        return .success("File '\(fileName)' will appear in \(dir.lastPathComponent) after \(delay)s.")
    }

    // MARK: Restore

    func restore(_ context: FaultContext) async -> Bool {
        switch id {
        case .storageFill:
            // Detach any ChaosTest volumes and delete images.
            _ = (try? Shell.sh("/usr/bin/hdiutil detach /Volumes/ChaosTest* -force 2>/dev/null; true"))
            let imageDir = ChaosSandbox.rootURL.appendingPathComponent("Images", isDirectory: true)
            try? FileManager.default.removeItem(at: imageDir)
            return true

        case .fsMissingFile:
            // Restore from vault: move items back based on manifest.
            let fm = FileManager.default
            guard let manifest = try? fm.contentsOfDirectory(at: vault, includingPropertiesForKeys: nil) else { return false }
            let dirPaths = manifest.filter { $0.lastPathComponent.hasPrefix("manifest-") }
            for manifestURL in dirPaths {
                let targetDir = (try? String(contentsOf: manifestURL, encoding: .utf8)) ?? ""
                let files = manifest.filter { $0.lastPathComponent.hasPrefix("manifest-") == false }
                for f in files {
                    let dest = URL(fileURLWithPath: targetDir).appendingPathComponent(f.lastPathComponent)
                    try? fm.moveItem(at: f, to: dest)
                }
                try? fm.removeItem(at: manifestURL)
            }
            return true

        case .fsReadOnly, .fsPermissionDenied, .permissionDenied:
            guard let dir = lastSnapshotDir(context) else { return false }
            let fm = FileManager.default
            var ok = true
            if let paths = try? fm.subpathsOfDirectory(atPath: dir.path) {
                for p in paths {
                    let full = dir.appendingPathComponent(p).path
                    var attrs = try? fm.attributesOfItem(atPath: full)
                    attrs?[.posixPermissions] = 0o644
                    do { try fm.setAttributes(attrs ?? [:], ofItemAtPath: full) } catch { ok = false }
                }
            }
            return ok

        case .fsLocked:
            for pid in Self.lockHolderPIDs { kill(pid, SIGKILL) }
            Self.lockHolderPIDs.removeAll()
            return true

        case .fsDelayedAvailability:
            ChaosSandbox.purgeAll()
            return true

        default:
            return false
        }
    }

    // MARK: Mode snapshots (for permission restore)

    private struct ModeSnapshot: Codable {
        var path: String
        var mode: Int
    }

    private func saveModeSnapshot(dir: URL, context: FaultContext) {
        let fm = FileManager.default
        var snapshots: [ModeSnapshot] = []
        if let paths = try? fm.subpathsOfDirectory(atPath: dir.path) {
            for p in paths.prefix(500) {
                let full = dir.appendingPathComponent(p).path
                if let attrs = try? fm.attributesOfItem(atPath: full),
                   let mode = attrs[.posixPermissions] as? Int {
                    snapshots.append(ModeSnapshot(path: full, mode: mode))
                }
            }
        }
        if let data = try? JSONEncoder().encode(snapshots) {
            try? data.write(to: vault.appendingPathComponent("modes-\(context.binding.id.uuidString).json"), options: .atomic)
        }
    }

    private func lastSnapshotDir(_ context: FaultContext) -> URL? {
        guard let data = try? Data(contentsOf: vault.appendingPathComponent("modes-\(context.binding.id.uuidString).json")),
              let snaps = try? JSONDecoder().decode([ModeSnapshot].self, from: data),
              let first = snaps.first
        else { return nil }
        return URL(fileURLWithPath: first.path).deletingLastPathComponent()
    }

    // MARK: Directory approval

    private func approvedDirectory(_ context: FaultContext) -> URL? {
        if let explicit = context.binding.parameters["directory"], !explicit.isEmpty {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: explicit, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: explicit)
            }
            return nil
        }
        return ChaosSandbox.makeExperimentDirectory()
    }
}
