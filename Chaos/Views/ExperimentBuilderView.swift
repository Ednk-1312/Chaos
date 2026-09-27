import SwiftUI
import ChaosKit

/// The visual experiment builder: fault library → timeline → inspector.
struct ExperimentBuilderView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = "Custom Experiment"
    @State private var bindings: [FaultBinding] = []
    @State private var assertions: [Assertion] = []
    @State private var selectedBindingID: UUID?
    @State private var showPreview = false

    private var totalDuration: Double { max(30, bindings.map { $0.startOffset + $0.duration }.max() ?? 30) }
    private var selectedBinding: FaultBinding? { bindings.first { $0.id == selectedBindingID } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                FaultLibraryPane { faultID in
                    addFault(faultID)
                }
                .frame(minWidth: 220, maxWidth: 280)

                TimelinePane(
                    bindings: $bindings,
                    selectedBindingID: $selectedBindingID,
                    onDuplicate: duplicateBinding,
                    onToggleEnabled: toggleEnabled,
                    onDelete: deleteBinding
                )
                .frame(minWidth: 460, maxWidth: .infinity, minHeight: 320)

                InspectorPane(
                    binding: selectedBinding,
                    onUpdate: { updated in
                        if let i = bindings.firstIndex(where: { $0.id == updated.id }) {
                            bindings[i] = updated
                        }
                    },
                    onDelete: { if let selected = selectedBinding { deleteBinding(selected) } }
                )
                .frame(minWidth: 260, maxWidth: 340)
            }
            Divider()
            AssertionsBar(assertions: $assertions)
        }
        .frame(minWidth: 1080, minHeight: 640)
        .sheet(isPresented: $showPreview) {
            ReviewChaosSheet(
                name: name, bindings: bindings, assertions: assertions,
                targets: app.primaryTarget.map { [$0] } ?? []
            ) { confirmedName in
                var config = ExperimentConfig(
                    name: confirmedName,
                    plannedDuration: totalDuration,
                    bindings: bindings,
                    targets: app.primaryTarget.map { [$0] } ?? [],
                    assertions: assertions
                )
                config.safetyConfirmed = true
                dismiss()
                app.launch(config)
            }
        }
    }

    // MARK: Actions (all real)

    private func addFault(_ faultID: FaultID) {
        let offset = bindings.map { $0.startOffset + $0.duration }.max() ?? 0
        let binding = FaultBinding(
            faultID: faultID,
            startOffset: offset,
            duration: FaultDefaults.duration(for: faultID),
            parameters: FaultDefaults.parameters(for: faultID)
        )
        bindings.append(binding)
        selectedBindingID = binding.id
    }

    private func duplicateBinding(_ binding: FaultBinding) {
        var copy = binding
        copy.id = UUID()
        copy.startOffset = binding.startOffset + binding.duration
        bindings.append(copy)
        selectedBindingID = copy.id
    }

    private func toggleEnabled(_ binding: FaultBinding) {
        if let i = bindings.firstIndex(where: { $0.id == binding.id }) {
            bindings[i].enabled.toggle()
        }
    }

    private func deleteBinding(_ binding: FaultBinding) {
        bindings.removeAll { $0.id == binding.id }
        if selectedBindingID == binding.id { selectedBindingID = nil }
    }

    private var header: some View {
        HStack {
            TextField("Experiment name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("REVIEW CHAOS") { showPreview = true }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(bindings.isEmpty)
        }
        .padding(14)
    }
}

// MARK: - Bottom: Assertions

struct AssertionsBar: View {
    @Binding var assertions: [Assertion]
    @State private var kind: Assertion.Kind = .processAlive
    @State private var subject = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Assertions").font(.headline)
                Picker("", selection: $kind) {
                    ForEach(Assertion.Kind.allCases, id: \.self) { k in
                        Text(k.rawValue).tag(k)
                    }
                }
                .labelsHidden().frame(width: 200)
                TextField("subject (pid / path / host:port / percent)", text: $subject)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Button("Add") {
                    guard !subject.isEmpty else { return }
                    assertions.append(Assertion(kind: kind, subject: subject))
                    subject = ""
                }
                Spacer()
            }
            if !assertions.isEmpty {
                // Chips flow on their own row and scroll horizontally instead of
                // stretching the bar past the window width.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(assertions) { assertion in
                            HStack(spacing: 3) {
                                Image(systemName: "checklist").font(.caption2)
                                Text(assertion.label).font(.caption2)
                                Button {
                                    assertions.removeAll { $0.id == assertion.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill").font(.caption2)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
