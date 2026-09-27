import SwiftUI
import ChaosKit

/// Visual WHEN/THEN editor for conditional chaos rules.
/// Only engine-observable triggers are offered (see ConditionalChaos.swift):
/// process exit, process appears, memory pressure threshold, endpoint down,
/// and another fault activating. Each rule fires at most once per experiment.
struct ConditionalChaosView: View {
    @EnvironmentObject private var app: AppModel
    @State private var rules: [ChaosRule] = []
    @State private var editingRule: DraftRule?
    @State private var editingID: UUID?

    struct DraftRule: Identifiable {
        var trigger: ChaosRule.TriggerKind = .memoryPressureExceeds
        var subject = "90"
        var actionFaultID = FaultID.cpuLoad
        var actionParameters: [String: String] = ["utilization": "75", "threads": "4"]
        var actionDuration: Double = 30
        var startOffset: Double = 0
        var enabled = true
        var id = UUID()   // sheet(item:) presentation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text("Conditional Chaos").font(.largeTitle.bold())
                    Text("Rules that watch real, observable system state and fire a fault in response. Each rule fires at most once per experiment.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    editingRule = DraftRule()
                    editingID = nil
                } label: {
                    Label("New Rule", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }

            Text("Chaos only offers triggers it can genuinely observe: a process exits, a process appears, memory pressure crosses a threshold, an endpoint stops accepting connections, or another fault activates.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if rules.isEmpty {
                EmptyStateView(
                    symbol: "arrow.triangle.branch",
                    title: "NO RULES YET",
                    message: "Create a WHEN/THEN rule — for example: WHEN memory pressure exceeds 70%, THEN begin CPU pressure.",
                    buttonTitle: "New Rule"
                ) {
                    editingRule = DraftRule()
                    editingID = nil
                }
            } else {
                ForEach(rules) { rule in
                    RuleCard(rule: rule) {
                        editingRule = DraftRule(
                            trigger: rule.trigger, subject: rule.subject,
                            actionFaultID: rule.actionFaultID,
                            actionParameters: rule.actionParameters,
                            actionDuration: rule.actionDuration,
                            startOffset: rule.startOffset, enabled: rule.enabled
                        )
                        editingID = rule.id
                    } onDelete: {
                        rules.removeAll { $0.id == rule.id }
                    }
                }
            }

            if !rules.isEmpty {
                Button {
                    runWithRules()
                } label: {
                    Label("RUN WITH THESE RULES", systemImage: "bolt.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(app.isRunning)
            }
        }
        .padding(24)
        .navigationTitle("Conditional Chaos")
        .sheet(item: $editingRule) { draft in
            RuleEditorSheet(draft: draft, isNew: editingID == nil) { rule in
                if let id = editingID, let index = rules.firstIndex(where: { $0.id == id }) {
                    rules[index] = rule
                } else {
                    rules.append(rule)
                }
            }
        }
    }

    private func runWithRules() {
        guard let target = app.primaryTarget else { return }
        var config = ExperimentConfig(
            name: "Conditional Chaos",
            plannedDuration: 300,
            bindings: [],
            targets: [target],
            rules: rules
        )
        config.safetyConfirmed = true
        app.launch(config)
    }
}

// MARK: - Rule card (WHEN ↓ THEN visual)

struct RuleCard: View {
    let rule: ChaosRule
    var onEdit: () -> Void
    var onDelete: () -> Void

    private var triggerSubject: String {
        switch rule.trigger {
        case .processExit, .processAppears: return rule.subject
        case .memoryPressureExceeds: return "memory pressure > \(rule.subject)%"
        case .endpointDown: return "\(rule.subject) unreachable"
        case .faultActivated: return "\(rule.subject) activates"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text("WHEN \(triggerSubject)").font(.callout.bold())
                } icon: {
                    Image(systemName: "eye").foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                Label {
                    Text("THEN \(rule.actionFaultID.rawValue) for \(Int(rule.actionDuration))s")
                        .font(.callout.bold())
                        .foregroundStyle(.red)
                } icon: {
                    Image(systemName: "bolt.fill").foregroundStyle(.red)
                }
                if rule.startOffset > 0 {
                    Text("armed after \(Int(rule.startOffset))s")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Toggle("Enabled", isOn: Binding(
                    get: { rule.enabled },
                    set: { _ in onEdit() }   // edit sheet allows the change
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                HStack(spacing: 6) {
                    Button("Edit") { onEdit() }.controlSize(.small)
                    Button("Delete", role: .destructive) { onDelete() }
                        .controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
        .opacity(rule.enabled ? 1 : 0.55)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rule: when \(triggerSubject), then \(rule.actionFaultID.rawValue)")
    }
}

// MARK: - Rule editor

struct RuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: ConditionalChaosView.DraftRule
    let isNew: Bool
    var onSave: (ChaosRule) -> Void

    private var availableFaults: [FaultDescriptor] {
        FaultCatalog.all.filter { $0.category != .misc }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "New WHEN/THEN Rule" : "Edit Rule").font(.title3.bold())

            VStack(alignment: .leading, spacing: 10) {
                Label("WHEN", systemImage: "eye").font(.headline).foregroundStyle(.secondary)
                Picker("Trigger", selection: $draft.trigger) {
                    Text("a process exits").tag(ChaosRule.TriggerKind.processExit)
                    Text("a process appears").tag(ChaosRule.TriggerKind.processAppears)
                    Text("memory pressure exceeds").tag(ChaosRule.TriggerKind.memoryPressureExceeds)
                    Text("an endpoint goes down").tag(ChaosRule.TriggerKind.endpointDown)
                    Text("another fault activates").tag(ChaosRule.TriggerKind.faultActivated)
                }
                .labelsHidden()

                triggerSubjectField

                Divider()
                Label("THEN", systemImage: "bolt.fill").font(.headline).foregroundStyle(.red)
                Picker("Fault", selection: $draft.actionFaultID) {
                    ForEach(availableFaults, id: \.id) { fault in
                        Text("\(fault.name) — \(fault.severity.title) risk").tag(fault.id)
                    }
                }
                if let descriptor = FaultCatalog.descriptor(for: draft.actionFaultID) {
                    Text(descriptor.capabilityNote)
                        .font(.caption2).foregroundStyle(.tertiary)
                    if descriptor.simulated {
                        Text("SIMULATED — this fault does not affect the real system; see documentation.")
                            .font(.caption2.bold()).foregroundStyle(.purple)
                    }
                }
                HStack {
                    Text("Duration: \(Int(draft.actionDuration))s").frame(width: 120, alignment: .leading)
                    Slider(value: $draft.actionDuration, in: 5...300, step: 5)
                }
                HStack {
                    Text("Armed after: \(Int(draft.startOffset))s").frame(width: 120, alignment: .leading)
                    Slider(value: $draft.startOffset, in: 0...240, step: 5)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.6)))

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Rule") {
                    let rule = ChaosRule(
                        trigger: draft.trigger,
                        subject: draft.subject,
                        actionFaultID: draft.actionFaultID,
                        actionParameters: draft.actionParameters,
                        actionDuration: draft.actionDuration,
                        startOffset: draft.startOffset,
                        enabled: draft.enabled
                    )
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!subjectValid)
            }
        }
        .padding(22)
        .frame(width: 520)
    }

    @ViewBuilder
    private var triggerSubjectField: some View {
        switch draft.trigger {
        case .memoryPressureExceeds:
            HStack {
                Text("Threshold:").foregroundStyle(.secondary)
                TextField("90", text: $draft.subject).frame(width: 80)
                Text("% (system memory pressure 0–100)").font(.caption).foregroundStyle(.tertiary)
            }
        case .endpointDown:
            HStack {
                Text("Endpoint:").foregroundStyle(.secondary)
                TextField("api.example.com:443", text: $draft.subject).frame(width: 220)
            }
        case .processAppears:
            HStack {
                Text("Process name:").foregroundStyle(.secondary)
                TextField("helper process name", text: $draft.subject).frame(width: 220)
            }
        case .processExit:
            HStack {
                Text("PID to watch:").foregroundStyle(.secondary)
                TextField("1234", text: $draft.subject).frame(width: 100)
            }
        case .faultActivated:
            Picker("Fault", selection: $draft.subject) {
                ForEach(FaultCatalog.all, id: \.id) { fault in
                    Text(fault.name).tag(fault.id.rawValue)
                }
            }
        }
    }

    private var subjectValid: Bool {
        switch draft.trigger {
        case .processExit: return Int32(draft.subject) != nil
        case .memoryPressureExceeds: return Double(draft.subject) != nil
        default: return !draft.subject.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}
