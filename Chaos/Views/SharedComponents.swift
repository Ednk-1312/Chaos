import SwiftUI
import ChaosKit

// MARK: - Empty states (Section 19: no bare "No items.")

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Experiment row (used by history, dashboard, compare picker)

struct ExperimentRow: View {
    let record: ExperimentRecord
    var showTarget = true

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: record.outcome.symbolName)
                .foregroundStyle(Self.color(for: record.outcome))
            VStack(alignment: .leading, spacing: 2) {
                Text(record.config.name).font(.headline).lineLimit(1)
                HStack(spacing: 6) {
                    if showTarget, let target = record.config.targets.first {
                        Text(target.name)
                    }
                    Text("\(record.config.bindings.count) faults")
                    Text("seed \(record.config.seed)")
                    if let duration = record.duration {
                        Text(duration.asClockString)
                    }
                    let summary = record.assertionSummary
                    if summary.failed > 0 {
                        Text("\(summary.failed) failed").foregroundStyle(.red)
                    } else if summary.passed > 0 {
                        Text("\(summary.passed) passed").foregroundStyle(.green)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if !record.restorationStatus.isEmpty, record.restorationStatus.values.contains(false) {
                Label("Restoration", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("Some subsystems did not verify as restored")
            }
            Text(record.startedAt.map { RecentExperimentRow.dateFormatter.string(from: $0) } ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.config.name): \(record.outcome.title)")
    }

    static func color(for outcome: ExperimentOutcome) -> Color {
        switch outcome {
        case .passed: return .green
        case .failed: return .red
        case .warning: return .orange
        case .running: return .orange
        case .errored: return .red
        default: return .secondary
        }
    }
}

// MARK: - Recipe fault sequence (the "0s 500ms latency" block)

struct RecipeSequenceView: View {
    let bindings: [FaultBinding]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(bindings) { binding in
                HStack(spacing: 8) {
                    Text(String(format: "%4ds", Int(binding.startOffset)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 1, height: 10)
                    Text(binding.name).font(.caption)
                    Text("for \(Int(binding.duration))s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if !binding.enabled {
                        Text("disabled").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

// MARK: - Fault summary line (name + primary parameter, honest labels)

struct FaultSummaryLine: View {
    let binding: FaultBinding

    private var parameterSummary: String {
        switch binding.faultID.rawValue {
        case "network.latency", "dependency.slow":
            return binding.parameters["latencyMs"].map { "\($0)ms" } ?? ""
        case "network.packet_loss":
            return binding.parameters["lossPercent"].map { "\($0)%" } ?? ""
        case "network.bandwidth":
            return binding.parameters["bandwidthKbps"].map { "\($0) kbps" } ?? ""
        case "memory.pressure":
            return binding.parameters["gigabytes"].map { "\($0) GB" } ?? ""
        case "cpu.load":
            return binding.parameters["utilization"].map { "\($0)%" } ?? ""
        case "storage.fill":
            return binding.parameters["capacityGB"].map { "\($0) GB" } ?? ""
        default:
            return ""
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if let descriptor = FaultCatalog.descriptor(for: binding.faultID) {
                Image(systemName: descriptor.category.symbolName)
                    .font(.caption)
                    .foregroundStyle(descriptor.severityColor)
                    .frame(width: 16)
            }
            Text(binding.name).font(.callout)
            if !parameterSummary.isEmpty {
                Text(parameterSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(binding.startOffset))s → \(Int(binding.duration))s")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
