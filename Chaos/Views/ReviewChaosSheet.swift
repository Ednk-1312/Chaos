import SwiftUI
import ChaosKit

/// Pre-flight review shown before any experiment runs. Never hides consequences.
struct ReviewChaosSheet: View {
    let name: String
    let bindings: [FaultBinding]
    let assertions: [Assertion]
    let targets: [TargetDescriptor]
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editableName: String = ""

    private var duration: TimeInterval {
        max(30, bindings.map { $0.startOffset + $0.duration }.max() ?? 30)
    }
    private var maxSeverity: Severity { bindings.map(\.severity).max() ?? .low }
    private var needsPrivileges: Bool {
        bindings.contains { FaultCatalog.descriptor(for: $0.faultID)?.privileges != .none }
    }
    private var hasSimulated: Bool {
        bindings.contains { FaultCatalog.descriptor(for: $0.faultID)?.simulated == true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("REVIEW CHAOS").font(.title2.bold()).foregroundStyle(.red)

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow {
                    Text("Target").foregroundStyle(.secondary)
                    Text(targets.first.map { "\($0.name)\($0.pid.map { " (pid \($0))" } ?? "")" } ?? "System-wide (no specific target)")
                }
                GridRow {
                    Text("Duration").foregroundStyle(.secondary)
                    Text("\(Int(duration)) seconds")
                }
                GridRow {
                    Text("Risk").foregroundStyle(.secondary)
                    Label(maxSeverity.title, systemImage: "gauge.with.needle")
                        .foregroundStyle(maxSeverity.riskColor)
                }
                GridRow {
                    Text("Privileges").foregroundStyle(.secondary)
                    Text(needsPrivileges ? "Administrator authorization required" : "None")
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("What will happen").font(.headline)
                ForEach(bindings.sorted(by: { $0.startOffset < $1.startOffset })) { binding in
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int(binding.startOffset))s")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                        Text(binding.name)
                        if !binding.parameters.isEmpty {
                            Text(binding.parameters.sorted { $0.key < $1.key }
                                .map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(binding.duration))s").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    }
                }
            }

            if !assertions.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    Text("Assertions").font(.headline)
                    ForEach(assertions) { assertion in
                        Label(assertion.label, systemImage: "checklist")
                            .font(.callout)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Text("Safety").font(.headline)
                Label("Automatic restoration with per-fault verification", systemImage: "checkmark.circle")
                Label("No permanent file modification (sandbox vaults only)", systemImage: "checkmark.circle")
                Label("Memory pressure capped — always leaves ≥2 GB or 25% of RAM free", systemImage: "checkmark.circle")
                Label("Emergency stop available at any time (⌘.)", systemImage: "checkmark.circle")
                if hasSimulated {
                    Label("Includes SIMULATED components — see fault documentation", systemImage: "waveform.path.ecg")
                        .foregroundStyle(.purple)
                }
            }
            .font(.callout)

            Divider()

            HStack {
                TextField("Experiment name", text: $editableName)
                    .textFieldStyle(.roundedBorder)
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("CREATE CHAOS") {
                    onConfirm(editableName.isEmpty ? name : editableName)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(24)
        .frame(width: 540)
        .onAppear { editableName = name }
    }
}

extension Severity {
    var riskColor: Color {
        switch self {
        case .low: return .green
        case .moderate: return .orange
        case .high: return .red
        case .extreme: return .purple
        }
    }
}
