import SwiftUI
import ChaosKit

struct SystemMonitorView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("System").font(.largeTitle.bold())
                SystemHealthRow(stats: app.systemStats)
                if let s = app.systemStats {
                    Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 8) {
                        GridRow {
                            Text("Compressed memory").foregroundStyle(.secondary)
                            Text(ByteCount.string(s.memoryCompressedBytes))
                        }
                        GridRow {
                            Text("Swap used").foregroundStyle(.secondary)
                            Text(ByteCount.string(s.swapUsedBytes))
                        }
                        GridRow {
                            Text("Processes").foregroundStyle(.secondary)
                            Text("\(s.processCount)")
                        }
                    }
                }
                HStack {
                    Text("Chaos-induced load is shown in the Live Experiment view; these numbers include it.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(24)
        }
        .navigationTitle("System")
    }
}

struct NetworkMonitorView: View {
    @EnvironmentObject private var app: AppModel
    @State private var history: [(Double, Double)] = []

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Network").font(.largeTitle.bold())
            if let s = app.systemStats {
                HStack {
                    MetricCard(title: "In", value: ByteCount.string(UInt64(max(0, s.networkInBytesPerSec))) + "/s", symbol: "arrow.down")
                    MetricCard(title: "Out", value: ByteCount.string(UInt64(max(0, s.networkOutBytesPerSec))) + "/s", symbol: "arrow.up")
                }
            }
            if app.isRunning {
                Label("A network fault may be altering these numbers — that's the point.", systemImage: "bolt.fill")
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(24)
        .onReceive(timer) { _ in
            if let s = app.systemStats {
                history.append((s.networkInBytesPerSec, s.networkOutBytesPerSec))
                if history.count > 60 { history.removeFirst() }
            }
        }
        .navigationTitle("Network")
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
    }
}

struct ProcessMonitorView: View {
    @State private var processes: [ProcessInfoSnapshot] = []
    @State private var searchText = ""

    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    private var filtered: [ProcessInfoSnapshot] {
        searchText.isEmpty ? processes : processes.filter { $0.command.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Processes").font(.largeTitle.bold())
            Table(filtered, selection: .constant(nil)) {
                TableColumn("PID") { p in Text("\(p.pid)").monospacedDigit() }.width(70)
                TableColumn("Name") { p in Text(p.shortName) }
                TableColumn("CPU") { p in Text(p.cpuPercent.asPercentString).monospacedDigit() }.width(70)
                TableColumn("Memory") { p in Text(ByteCount.string(p.rssBytes)).monospacedDigit() }.width(100)
                TableColumn("Command") { p in Text(p.command).lineLimit(1).foregroundStyle(.secondary) }
            }
        }
        .padding(24)
        .searchable(text: $searchText)
        .onReceive(timer) { _ in
            processes = ProcessScanner.snapshot().sorted { $0.cpuPercent > $1.cpuPercent }
        }
        .navigationTitle("Processes")
    }
}

struct StorageMonitorView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Storage").font(.largeTitle.bold())
            if let s = app.systemStats {
                let usedFraction = s.diskTotalBytes > 0
                    ? 1.0 - Double(s.diskFreeBytes) / Double(s.diskTotalBytes)
                    : 0
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: usedFraction)
                        .progressViewStyle(.linear)
                    Text("\(ByteCount.string(s.diskFreeBytes)) free of \(ByteCount.string(s.diskTotalBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Chaos never fills your real disk. Storage faults use temporary test volumes that are unmounted and deleted on restore.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
        .navigationTitle("Storage")
    }
}

struct MemoryMonitorView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Memory").font(.largeTitle.bold())
            if let s = app.systemStats {
                let usedFraction = s.memoryTotalBytes > 0
                    ? Double(s.memoryUsedBytes) / Double(s.memoryTotalBytes)
                    : 0
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: min(1, usedFraction)).progressViewStyle(.linear)
                    Text("\(ByteCount.string(s.memoryUsedBytes)) of \(ByteCount.string(s.memoryTotalBytes)) active+wired")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 8) {
                    GridRow {
                        Text("Compressed").foregroundStyle(.secondary)
                        Text(ByteCount.string(s.memoryCompressedBytes)).monospacedDigit()
                    }
                    GridRow {
                        Text("Swap").foregroundStyle(.secondary)
                        Text(ByteCount.string(s.swapUsedBytes)).monospacedDigit()
                    }
                }
                Text("Memory faults respect a hard ceiling: Chaos always leaves at least 2 GB (or 25% of RAM) free.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(24)
        .navigationTitle("Memory")
    }
}
