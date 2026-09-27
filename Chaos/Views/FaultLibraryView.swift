import SwiftUI
import ChaosKit

struct FaultLibraryView: View {
    @State private var selected: FaultDescriptor?
    @State private var searchText = ""

    private var filtered: [(FaultCategory, [FaultDescriptor])] {
        FaultCatalog.byCategory().map { (category, faults) in
            (category, searchText.isEmpty ? faults : faults.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.whatItTests.localizedCaseInsensitiveContains(searchText)
            })
        }
        .filter { !$0.1.isEmpty }
    }

    var body: some View {
        // HSplitView (NOT a nested NavigationSplitView — nesting splits inside
        // RootView's split view corrupts the outer sidebar's layout).
        HSplitView {
            Group {
            List(selection: $selected) {
                ForEach(filtered, id: \.0) { category, faults in
                    Section(category.title) {
                        ForEach(faults, id: \.id) { fault in
                            HStack {
                                Image(systemName: fault.simulated ? "waveform.path.ecg.rectangle" : "bolt.fill")
                                    .foregroundStyle(fault.severityColor)
                                VStack(alignment: .leading) {
                                    Text(fault.name)
                                    Text(fault.id.rawValue).font(.caption2.monospaced()).foregroundStyle(.secondary)
                                }
                            }
                            .tag(fault)
                        }
                    }
                }
            }
            .searchable(text: $searchText)
            }
            .frame(minWidth: 280, maxWidth: 420, maxHeight: .infinity)

            Group {
                if let fault = selected {
                    FaultDetailView(fault: fault)
                } else {
                    Text("Select a fault to read its documentation").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Fault Library")
    }
}

extension FaultDescriptor {
    var severityColor: Color {
        switch severity {
        case .low: return .green
        case .moderate: return .yellow
        case .high: return .orange
        case .extreme: return .red
        }
    }
}

struct FaultDetailView: View {
    let fault: FaultDescriptor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading) {
                        Text(fault.name).font(.largeTitle.bold())
                        Text(fault.id.rawValue).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Label(fault.severity.title, systemImage: "gauge.with.needle")
                            .foregroundStyle(fault.severityColor)
                        if fault.simulated {
                            Label("SIMULATED", systemImage: "waveform.path.ecg")
                                .font(.caption.bold())
                                .foregroundStyle(.purple)
                        }
                    }
                }

                Text(fault.summary).font(.body)

                docSection("What It Tests", fault.whatItTests)
                docSection("What macOS Allows", fault.capabilityNote)
                docSection("How Restoration Works", fault.restoration)

                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        Text("Category").foregroundStyle(.secondary)
                        Text(fault.category.title)
                    }
                    GridRow {
                        Text("Reversible").foregroundStyle(.secondary)
                        Text(fault.reversible ? "Yes" : "No — guided only")
                    }
                    GridRow {
                        Text("Privileges").foregroundStyle(.secondary)
                        Text(privilegeText)
                    }
                    GridRow {
                        Text("Default Duration").foregroundStyle(.secondary)
                        Text("\(Int(fault.defaultDuration))s")
                    }
                }
            }
            .padding(24)
        }
    }

    private var privilegeText: String {
        switch fault.privileges {
        case .none: return "None"
        case .localNetworkSettings: return "OS authorization prompt (pf/dummynet)"
        case .systemConfiguration: return "Network configuration"
        case .accessibility: return "Accessibility (guided only)"
        case .adminExplanation: return "Explained at point of need"
        }
    }

    private func docSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(body).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}
