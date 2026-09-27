import SwiftUI

struct YourDataView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your Data").font(.largeTitle.bold())
                    Text("Chaos is local-first. This page states exactly what that means.")
                        .foregroundStyle(.secondary)
                }

                trustRow(icon: "internaldrive", color: .green,
                         title: "Everything is stored on your Mac",
                         detail: "Experiments, records, recipes, suites, and reports live under ~/Library/Application Support/Chaos. Delete that folder and Chaos forgets everything.")

                trustRow(icon: "wifi.slash", color: .green,
                         title: "Nothing is uploaded — there is no upload",
                         detail: "Chaos contains no telemetry, no analytics, and no cloud client. It never opens an outbound connection on its own (network faults touch the system packet filter, not any server).")

                trustRow(icon: "doc.text", color: .green,
                         title: "Your source code is never read",
                         detail: "Chaos observes applications from the outside: process tables, CPU/memory sampling, TCP reachability. It does not read source files, documents, or app contents.")

                trustRow(icon: "square.and.arrow.up", color: .orange,
                         title: "Exports are the only way data leaves",
                         detail: "Reports (Markdown, JSON, CSV, PDF) go wherever you choose to save or send them. Chaos does not send anything anywhere by itself.")

                trustRow(icon: "person.crop.circle.badge.xmark", color: .green,
                         title: "No accounts, no identifiers",
                         detail: "No sign-in, no device ID, no crash reporting service. The only identifiers are random UUIDs for your own experiments.")

                Text("Verification: the ChaosKit engine contains no networking client code. The only outbound traffic during experiments is dummynet-shaped pass-through traffic of your own applications, plus optional TCP reachability probes to endpoints you explicitly configure in assertions.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(24)
        }
        .navigationTitle("Your Data")
    }

    private func trustRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
    }
}
