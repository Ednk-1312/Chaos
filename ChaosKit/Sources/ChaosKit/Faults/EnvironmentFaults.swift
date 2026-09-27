import Foundation

final class EnvironmentFaultRunner: FaultRunner {
    let id: FaultID

    init(id: FaultID) { self.id = id }

    func activate(_ context: FaultContext) async -> ActivationResult {
        switch id {
        // MARK: Lifecycle

        case .lifecycleSleep:
            let r = (try? Shell.run("/usr/bin/pmset", ["sleepnow"]))
                ?? ShellResult(exitCode: 1, stdout: "", stderr: "pmset failed")
            guard r.succeeded else { return .failure("Sleep request was refused (need user session / approval).") }
            return .success("System sleep requested — observe reconnect behavior on wake.")

        case .lifecycleWake:
            // Compose: block network now; the user wakes the Mac; first minutes are offline.
            let script = "/sbin/pfctl -E >/dev/null 2>&1; echo \"block drop out all\" | /sbin/pfctl -a com.chaos -f -"
            let r = Elevation.runPrivileged(script)
            guard r.succeeded else { return .failure("Could not install offline rule.") }
            return .success("Offline-until-notice active: after wake, network stays blocked until restoration.")

        // MARK: Device

        case .deviceVolumeDisappear:
            return await activateVolumeDisappear(context)

        case .deviceDisconnect:
            return .success(
                "Guided drill: disconnect the device now (Chaos cannot unplug hardware). "
                + "Expected behavior checklist is attached to this event."
            )

        case .deviceDisplaySleep:
            let r = (try? Shell.run("/usr/bin/pmset", ["displaysleepnow"]))
                ?? ShellResult(exitCode: 1, stdout: "", stderr: "pmset failed")
            guard r.succeeded else { return .failure("Display sleep refused.") }
            return .success("Display sleep requested.")

        case .deviceAudioSwitch:
            return .success(
                "SIMULATED/Guided: switch your audio output now (Chaos cannot alter CoreAudio routes for other apps)."
            )

        // MARK: Clock

        case .clockSkew, .clockDST, .clockRollover, .clockCertExpiry:
            return await activateClockFault(context)

        // MARK: Power

        case .powerLowBattery, .powerChargeState, .powerSourceSwitch:
            return .success(
                "SIMULATED: power state published to the Chaos feed only — system hardware state is untouched. "
                + "Pair with the guided drill for real transitions."
            )

        case .powerThermal, .thermalSustainedLoad:
            // Routed to resource supervisor at registration time; fallback here for safety.
            let supervisorOK = StressWorkerSupervisor.shared.startCPUWorkers(
                utilization: id == .powerThermal ? 90 : 35,
                threadCount: max(2, ProcessInfo.processInfo.activeProcessorCount / 2),
                durationSeconds: max(5, Int(context.binding.duration))
            )
            guard !supervisorOK.isEmpty else { return .failure("Could not spawn load workers.") }
            return .success("Workload-based thermal pressure active.")

        default:
            return .failure("EnvironmentFaultRunner cannot execute \(id.rawValue).")
        }
    }

    // MARK: Volume disappear

    private func activateVolumeDisappear(_ context: FaultContext) async -> ActivationResult {
        let imageDir = ChaosSandbox.rootURL.appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)
        let imagePath = imageDir.appendingPathComponent("chaos-usb-\(Int.random(in: 1000...9999)).dmg").path

        let create = (try? Shell.run("/usr/bin/hdiutil", [
            "create", "-size", "64m", "-type", "UDIF", "-fs", "HFS+",
            "-volname", "ChaosUSB", imagePath
        ])) ?? ShellResult(exitCode: 1, stdout: "", stderr: "")
        guard create.succeeded else { return .failure("Could not create removable-like test volume.") }

        let attach = (try? Shell.run("/usr/bin/hdiutil", ["attach", imagePath, "-nobrowse"]))
            ?? ShellResult(exitCode: 1, stdout: "", stderr: "")
        guard attach.succeeded else { return .failure("Could not attach test volume.") }

        // Let the target observe it, then yank it mid-experiment.
        let delay = max(2, context.intParam("detachAfterSeconds", default: 5))
        DispatchQueue.global().asyncAfter(deadline: .now() + TimeInterval(delay)) {
            _ = (try? Shell.run("/usr/bin/hdiutil", ["detach", "/Volumes/ChaosUSB", "-force"]))
        }
        return .success("Test volume mounted at /Volumes/ChaosUSB — detaches in \(delay)s.")
    }

    // MARK: Clock faults

    private func activateClockFault(_ context: FaultContext) async -> ActivationResult {
        let dir = ChaosSandbox.makeExperimentDirectory()
        switch id {
        case .clockSkew:
            let offset = context.intParam("offsetMinutes", default: 90)
            let feed = dir.appendingPathComponent("chaos-time-feed.json")
            let payload: [String: Any] = [
                "mode": "offset",
                "offsetMinutes": offset,
                "anchor": ISO8601DateFormatter().string(from: Date()),
                "note": "SIMULATED — apps must opt in via the Chaos time feed."
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted) {
                try? data.write(to: feed)
            }
            return .success("SIMULATED clock skew (\(offset) min) published at \(feed.path).")

        case .clockDST:
            let tz = context.param("timezone", default: "America/New_York")
            let feed = dir.appendingPathComponent("chaos-time-feed.json")
            let payload: [String: Any] = [
                "mode": "timezone",
                "timezone": tz,
                "note": "SIMULATED — launch your app with TZ=\(tz) via Chaos launch profiles."
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted) {
                try? data.write(to: feed)
            }
            return .success("SIMULATED DST profile (\(tz)) published.")

        case .clockRollover:
            let feed = dir.appendingPathComponent("chaos-time-feed.json")
            let payload: [String: Any] = [
                "mode": "rollover",
                "nextBoundary": ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400)),
                "note": "SIMULATED — boundary published for opt-in test builds."
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted) {
                try? data.write(to: feed)
            }
            return .success("SIMULATED rollover boundary published.")

        case .clockCertExpiry:
            // Generate an expired certificate locally with openssl for real trust-evaluation testing.
            let certDir = dir.appendingPathComponent("expired-cert", isDirectory: true)
            try? FileManager.default.createDirectory(at: certDir, withIntermediateDirectories: true)
            let key = certDir.appendingPathComponent("key.pem").path
            let cert = certDir.appendingPathComponent("expired.pem").path
            let r = (try? Shell.run("/usr/bin/openssl", [
                "req", "-x509", "-newkey", "rsa:2048", "-keyout", key, "-out", cert,
                "-days", "-30", "-nodes", "-subj", "/CN=chaos.expired.test"
            ])) ?? ShellResult(exitCode: 1, stdout: "", stderr: "")
            guard r.succeeded else { return .failure("openssl unavailable — guided fallback only.") }
            return .success("Expired certificate generated at \(cert) — point your TLS stack at it.")

        default:
            return .failure("unreachable")
        }
    }

    // MARK: Restore

    func restore(_ context: FaultContext) async -> Bool {
        switch id {
        case .lifecycleWake, .deviceDisconnect:
            return Elevation.runPrivileged(
                "/sbin/pfctl -a com.chaos -F all 2>/dev/null; exit 0", allowPrompt: false
            ).succeeded
        case .deviceVolumeDisappear:
            _ = (try? Shell.sh("/usr/bin/hdiutil detach /Volumes/ChaosUSB -force 2>/dev/null; true"))
            return true
        case .clockSkew, .clockDST, .clockRollover, .clockCertExpiry:
            ChaosSandbox.purgeAll()
            return true
        case .powerThermal, .thermalSustainedLoad:
            return StressWorkerSupervisor.shared.stopAll()
        default:
            return true
        }
    }
}
