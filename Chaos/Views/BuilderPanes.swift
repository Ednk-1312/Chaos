import SwiftUI
import ChaosKit

// MARK: - Left: Fault Library

struct FaultLibraryPane: View {
    let onAdd: (FaultID) -> Void

    private var groups: [(String, [FaultDescriptor])] {
        FaultCatalog.byCategory().map { ($0.0.title, $0.1) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Click or drag a fault into the timeline.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                ForEach(groups, id: \.0) { group, faults in
                    Text(group).font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(faults, id: \.id) { fault in
                        FaultLibraryRow(fault: fault, onAdd: onAdd)
                    }
                }
            }
            .padding(12)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
    }
}

struct FaultLibraryRow: View {
    let fault: FaultDescriptor
    let onAdd: (FaultID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: fault.category.symbolName)
                    .foregroundStyle(fault.severityColor)
                Text(fault.name).font(.callout).lineLimit(1)
                Spacer()
                if fault.simulated {
                    Text("SIM").font(.caption2.bold()).foregroundStyle(.purple)
                }
                if fault.privileges != .none {
                    Image(systemName: "key").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(fault.whatItTests).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(object: fault.id.rawValue as NSString) }
        .onTapGesture { onAdd(fault.id) }
        .help("\(fault.name) — \(fault.whatItTests)")
        .accessibilityLabel("Add \(fault.name) fault to timeline")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Center: Timeline

struct TimelinePane: View {
    @Binding var bindings: [FaultBinding]
    @Binding var selectedBindingID: UUID?
    let onDuplicate: (FaultBinding) -> Void
    let onToggleEnabled: (FaultBinding) -> Void
    let onDelete: (FaultBinding) -> Void

    @State private var zoom: Double = 1.0
    @State private var dropTargeted = false

    private var effectiveDuration: Double { max(30, bindings.map { $0.startOffset + $0.duration }.max() ?? 30) }
    private var pixelsPerSecond: Double { 12 * zoom }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Timeline").font(.headline)
                Text("\(Int(effectiveDuration))s").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button { withAnimation { zoom = min(4, zoom * 1.5) } } label: { Image(systemName: "plus.magnifyingglass") }
                Button { withAnimation { zoom = max(0.4, zoom / 1.5) } } label: { Image(systemName: "minus.magnifyingglass") }
            }
            .padding(.horizontal, 14)

            ScrollView([.horizontal]) {
                VStack(alignment: .leading, spacing: 4) {
                    ruler
                    ForEach(Array(lanes.enumerated()), id: \.offset) { _, lane in
                        LaneRow(
                            lane: lane,
                            bindings: $bindings,
                            selectedBindingID: $selectedBindingID,
                            pixelsPerSecond: pixelsPerSecond,
                            onDuplicate: onDuplicate,
                            onToggleEnabled: onToggleEnabled,
                            onDelete: onDelete
                        )
                    }
                    if bindings.isEmpty && !dropTargeted {
                        Text("Drag a fault here — a sensible default configuration is applied automatically.")
                            .font(.callout).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 110, alignment: .center)
                    }
                    if dropTargeted {
                        Text("Release to add the fault to the timeline")
                            .font(.callout).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, minHeight: 110, alignment: .center)
                    }
                }
                .frame(
                    minWidth: CGFloat(effectiveDuration) * pixelsPerSecond + 60,
                    minHeight: 260, alignment: .topLeading
                )
                .padding(.horizontal, 14)
            }
            .onDrop(of: [.text], isTargeted: $dropTargeted) { providers in
                handleDrop(providers)
            }
        }
        .padding(.vertical, 10)
    }

    private var ruler: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<Int(effectiveDuration / 10) + 1, id: \.self) { tick in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(tick * 10)s").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(width: 1, height: 6)
                }
                .frame(width: CGFloat(10 * pixelsPerSecond), alignment: .leading)
            }
            Spacer(minLength: 0)
        }
    }

    /// Lane assignment: place each binding in the first lane where it doesn't overlap.
    private var lanes: [[FaultBinding]] {
        var lanes: [[FaultBinding]] = []
        for binding in bindings.sorted(by: { $0.startOffset < $1.startOffset }) {
            var placed = false
            for i in lanes.indices {
                if lanes[i].allSatisfy({ $0.startOffset + $0.duration <= binding.startOffset + 0.01 }) {
                    lanes[i].append(binding)
                    placed = true
                    break
                }
            }
            if !placed { lanes.append([binding]) }
        }
        return lanes
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let raw = object as? String,
                  let descriptor = FaultCatalog.all.first(where: { $0.id.rawValue == raw })
            else { return }
            DispatchQueue.main.async {
                let offset = bindings.map { $0.startOffset + $0.duration }.max() ?? 0
                let binding = FaultBinding(
                    faultID: descriptor.id,
                    startOffset: offset,
                    duration: FaultDefaults.duration(for: descriptor.id),
                    parameters: FaultDefaults.parameters(for: descriptor.id)
                )
                bindings.append(binding)
                selectedBindingID = binding.id
                dropTargeted = false
            }
        }
        return true
    }
}

struct LaneRow: View {
    let lane: [FaultBinding]
    @Binding var bindings: [FaultBinding]
    @Binding var selectedBindingID: UUID?
    let pixelsPerSecond: Double
    let onDuplicate: (FaultBinding) -> Void
    let onToggleEnabled: (FaultBinding) -> Void
    let onDelete: (FaultBinding) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(lane) { binding in
                TimelineBlock(
                    binding: binding,
                    selected: selectedBindingID == binding.id,
                    pixelsPerSecond: pixelsPerSecond,
                    onSelect: { selectedBindingID = binding.id },
                    onMove: { newOffset in
                        if let i = bindings.firstIndex(where: { $0.id == binding.id }) {
                            bindings[i].startOffset = max(0, newOffset)
                        }
                    },
                    onResize: { newDuration in
                        if let i = bindings.firstIndex(where: { $0.id == binding.id }) {
                            bindings[i].duration = max(5, newDuration)
                        }
                    },
                    onDuplicate: { onDuplicate(binding) },
                    onToggleEnabled: { onToggleEnabled(binding) },
                    onDelete: { onDelete(binding) }
                )
            }
            Spacer(minLength: 0)
        }
        .frame(height: 42)
    }
}

struct TimelineBlock: View {
    let binding: FaultBinding
    let selected: Bool
    let pixelsPerSecond: Double
    let onSelect: () -> Void
    let onMove: (TimeInterval) -> Void
    let onResize: (TimeInterval) -> Void
    let onDuplicate: () -> Void
    let onToggleEnabled: () -> Void
    let onDelete: () -> Void

    @State private var dragOffset: CGFloat = 0

    private var width: CGFloat { max(26, CGFloat(binding.duration * pixelsPerSecond)) }

    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(selected ? 0.95 : 0.75))
            Text(binding.name)
                .font(.caption2)
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 10)
            HStack {
                Spacer(minLength: 0)
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 6, height: 16)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                onResize(binding.duration + Double(value.translation.width) / pixelsPerSecond)
                            }
                    )
            }
            .padding(.trailing, 3)
        }
        .frame(width: width, height: 30)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(selected ? Color.white : Color.clear, lineWidth: 2)
        )
        .opacity(binding.enabled ? 1 : 0.35)
        .offset(x: dragOffset)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in dragOffset = value.translation.width }
                .onEnded { value in
                    onMove(binding.startOffset + Double(value.translation.width) / pixelsPerSecond)
                    dragOffset = 0
                }
        )
        .onTapGesture { onSelect() }
        .contextMenu {
            Button("Duplicate") { onDuplicate() }
            Button(binding.enabled ? "Disable" : "Enable") { onToggleEnabled() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
        .accessibilityLabel("\(binding.name), from \(Int(binding.startOffset)) seconds, lasting \(Int(binding.duration)) seconds")
        .accessibilityHint("Use the context menu to duplicate, disable, or delete")
    }

    private var color: Color {
        if !binding.enabled { return .gray }
        switch binding.severity {
        case .low: return .green
        case .moderate: return .orange
        case .high: return .red
        case .extreme: return .purple
        }
    }
}

// MARK: - Right: Inspector

struct InspectorPane: View {
    let binding: FaultBinding?
    let onUpdate: (FaultBinding) -> Void
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            if let binding {
                VStack(alignment: .leading, spacing: 14) {
                    Text(binding.name).font(.headline)

                    if let descriptor = FaultCatalog.descriptor(for: binding.faultID) {
                        Label(descriptor.severity.title + " risk", systemImage: "gauge.with.needle")
                            .font(.caption)
                            .foregroundStyle(descriptor.severityColor)
                        if descriptor.simulated {
                            Label("SIMULATED — see documentation", systemImage: "waveform.path.ecg")
                                .font(.caption.bold()).foregroundStyle(.purple)
                        }
                    }

                    Toggle("Enabled", isOn: Binding(
                        get: { binding.enabled },
                        set: { onUpdate(bindingWith(binding, enabled: $0)) }
                    ))

                    if !Self.parameterFields(for: binding.faultID).isEmpty {
                        ParameterFields(binding: binding, onUpdate: onUpdate)
                    }

                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                        GridRow {
                            Text("Start").foregroundStyle(.secondary)
                            Slider(value: Binding(
                                get: { binding.startOffset },
                                set: { onUpdate(bindingWith(binding, startOffset: $0)) }
                            ), in: 0...600, step: 1)
                        }
                        GridRow {
                            Text("Duration").foregroundStyle(.secondary)
                            Slider(value: Binding(
                                get: { binding.duration },
                                set: { onUpdate(bindingWith(binding, duration: max(5, $0))) }
                            ), in: 5...600, step: 1)
                        }
                    }
                    HStack {
                        Text("\(Int(binding.startOffset))s → +\(Int(binding.duration))s")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                    }

                    if let descriptor = FaultCatalog.descriptor(for: binding.faultID) {
                        Divider()
                        Text(descriptor.capabilityNote).font(.caption).foregroundStyle(.secondary)
                        Text("Restore: \(descriptor.restoration)").font(.caption2).foregroundStyle(.tertiary)
                    }

                    Button("Delete Fault", role: .destructive) { onDelete() }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(14)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3").font(.largeTitle).foregroundStyle(.quaternary)
                    Text("Select a timeline block to configure it").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(14)
            }
        }
    }

    struct Field { let key: String; let defaultValue: String }

    static func parameterFields(for id: FaultID) -> [Field] {
        switch id {
        case .networkLatency, .dependencySlow, .jitter: return [Field(key: "latencyMs", defaultValue: "500")]
        case .packetLoss: return [Field(key: "lossPercent", defaultValue: "10")]
        case .bandwidthCap: return [Field(key: "bandwidthKbps", defaultValue: "1500")]
        case .burstLoss: return [Field(key: "periodSeconds", defaultValue: "12")]
        case .cpuLoad: return [Field(key: "utilization", defaultValue: "75"), Field(key: "threads", defaultValue: "4")]
        case .memoryPressure: return [Field(key: "gigabytes", defaultValue: "2")]
        case .storageFill: return [Field(key: "capacityGB", defaultValue: "2"), Field(key: "freeGB", defaultValue: "1")]
        case .deviceVolumeDisappear: return [Field(key: "detachAfterSeconds", defaultValue: "8")]
        case .processRestartLoop: return [Field(key: "intervalSeconds", defaultValue: "20")]
        case .dependencyDown, .dependencyFlap: return [Field(key: "port", defaultValue: "443")]
        default: return []
        }
    }

    private func bindingWith(_ binding: FaultBinding, enabled: Bool? = nil,
                             startOffset: TimeInterval? = nil, duration: TimeInterval? = nil,
                             parameters: [String: String]? = nil) -> FaultBinding {
        var copy = binding
        if let enabled { copy.enabled = enabled }
        if let startOffset { copy.startOffset = startOffset }
        if let duration { copy.duration = duration }
        if let parameters { copy.parameters = parameters }
        return copy
    }

}

/// Parameter text fields for the selected fault (extracted struct to avoid a
/// Swift 6.4 parser issue with computed @ViewBuilder functions inside View bodies).
private struct ParameterFields: View {
    let binding: FaultBinding
    let onUpdate: (FaultBinding) -> Void

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            ForEach(InspectorPane.parameterFields(for: binding.faultID), id: \.key) { field in
                GridRow {
                    Text(field.key).foregroundStyle(.secondary)
                    TextField("", text: Binding(
                        get: { binding.parameters[field.key] ?? field.defaultValue },
                        set: {
                            var p = binding.parameters
                            p[field.key] = $0
                            onUpdate(bindingWith(binding, parameters: p))
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                }
            }
        }
    }

    private func bindingWith(_ binding: FaultBinding, parameters: [String: String]) -> FaultBinding {
        var copy = binding
        copy.parameters = parameters
        return copy
    }
}
