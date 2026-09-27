import SwiftUI
import ChaosKit

struct RestoreCenterView: View {
    @EnvironmentObject private var app: AppModel
    @State private var sweepStatus: [String: Bool]?
    @State private var running = false
    @State private var showDetails = false

    private static let subsystemTitles: [String: String] = [
        "pf rules": "Packet Filter",
        "orphan workers": "CPU / Memory Workers",
        "stress.workers": "CPU / Memory Workers",
        "storage": "Storage Simulation",
        "filesystem": "Filesystem",
        "network": "Network",
        "process state": "Process State",
    ]

    private static let order = ["network", "pf rules", "orphan workers", "stress.workers",
                                "storage", "filesystem", "process state"]

    private var rows: [(String, Bool?)] {
        var items: [(String, Bool?)] = []
        if let sweep = sweepStatus {
            for (key, ok) in sweep.sorted(by: {
                (Self.order.firstIndex(of: $0.key) ?? 99) < (Self.order.firstIndex(of: $1.key) ?? 99)
            }) {
                items.append((key, ok))
            }
        } else if let record = app.liveRecord, !record.restorationStatus.isEmpty {
            for (key, ok) in record.restorationStatus.sorted(by: { $0.key < $1.key }) {
                items.append((key, ok))
            }
        } else {
            // Nothing has been touched by any experiment — say so honestly.
            items = [("network", nil), ("stress.workers", nil), ("storage", nil), ("filesystem", nil)]
        }
        return items
    }

    private var needsAttention: Bool {
        rows.contains { $0.1 == false }
    }
    private var anyVerified: Bool {
        rows.contains { $0.1 == true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text("Restore Center").font(.largeTitle.bold())
                    Text("Restoration is verified, never assumed. Green appears only after an actual verification — never because a cleanup was merely attempted.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    retry()
                } label: {
                    if running {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("RESTORE EVERYTHING", systemImage: "arrow.uturn.backward.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(running)
            }

            if needsAttention {
                // RESTORATION REQUIRED banner — never hidden.
                VStack(alignment: .leading, spacing: 8) {
                    Label("RESTORATION REQUIRED", systemImage: "exclamationmark.octagon.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text("One or more subsystems did not verify as restored. Retry the sweep; if it still fails, inspect the details below before trusting this machine's network state.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Retry") { retry() }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .disabled(running)
                        Button("Details") { showDetails = true }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.red.opacity(0.5)))
            } else if anyVerified {
                Label("SYSTEM STATE VERIFIED", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            }

            // SYSTEM STATE
            VStack(alignment: .leading, spacing: 4) {
                Text("SYSTEM STATE").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(rows, id: \.0) { subsystem, ok in
                    HStack {
                        switch ok {
                        case .some(true):
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(displayName(subsystem))
                            Spacer()
                            Text("Restored ✓ verified").font(.caption).foregroundStyle(.secondary)
                        case .some(false):
                            Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red)
                            Text(displayName(subsystem)).bold()
                            Spacer()
                            Text("NOT VERIFIED").font(.caption).foregroundStyle(.red)
                        case .none:
                            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                            Text(displayName(subsystem))
                            Spacer()
                            Text("No experiment has modified this").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(displayName(subsystem)): \(ok.map { $0 ? "restored and verified" : "not verified — needs attention" } ?? "untouched")")
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))

            if showDetails {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Details").font(.headline)
                    Text("Each check runs a real verification: the packet-filter anchor is flushed and then read back (an anchor that still contains rules reports failure), stress workers are killed by name and the process table is re-read to confirm none remain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let sweep = sweepStatus {
                        ForEach(sweep.sorted(by: { $0.key < $1.key }), id: \.key) { key, ok in
                            detailLine(key: key, ok: ok)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
            }

            Text("If Chaos itself crashes, the next launch sweeps for leftover state: stress workers are killed by name and network anchors are flushed.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .navigationTitle("Restore Center")
        .onAppear(perform: adoptLiveStatus)
        .onChange(of: app.lastRestoreStatus) { _ in adoptLiveStatus() }
    }

    private func adoptLiveStatus() {
        if sweepStatus == nil, let live = app.lastRestoreStatus, !live.isEmpty {
            sweepStatus = live
        }
    }

    private func retry() {
        running = true
        Task.detached {
            let status = FaultCleanup.restoreEverything()
            await MainActor.run {
                sweepStatus = status
                app.lastRestoreStatus = status
                running = false
            }
        }
    }

    private func displayName(_ key: String) -> String {
        Self.subsystemTitles[key] ?? key
    }

    private func detailLine(key: String, ok: Bool) -> some View {
        let verdict = ok ? "verified clean" : "VERIFICATION FAILED"
        let color: Color = ok ? .secondary : .red
        return Text("\(key): \(verdict)")
            .font(.caption)
            .foregroundStyle(color)
    }
}
