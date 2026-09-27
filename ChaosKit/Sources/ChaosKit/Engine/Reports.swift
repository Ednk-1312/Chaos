import Foundation
import AppKit
import WebKit

/// Generates shareable reports from experiment records.
public enum ReportGenerator {
    // MARK: Markdown

    public static func markdown(for record: ExperimentRecord) -> String {
        var out = "# Chaos Report — \(record.config.name)\n\n"
        out += "**Result:** \(record.outcome.title)  \n"
        out += "**Started:** \(record.startedAt.map { Self.formatter.string(from: $0) } ?? "—")  \n"
        out += "**Duration:** \(record.duration.map { $0.asClockString } ?? "—")  \n"
        out += "**Seed:** \(record.config.seed)  \n\n"

        if let host = record.hostInfo {
            out += "## System\n\n- \(host.hostname), \(host.chipName), \(host.macosVersion)\n- ChaosKit \(host.chaosVersion)\n\n"
        }

        out += "## Targets\n\n"
        for t in record.config.targets {
            out += "- \(t.name) (\(t.kind.rawValue))\(t.pid.map { " — pid \($0)" } ?? "")\n"
        }

        out += "\n## Faults\n\n"
        for b in record.config.bindings {
            out += "- \(b.name) @ \(Int(b.startOffset))s for \(Int(b.duration))s (`\(b.faultID.rawValue)`)\n"
        }

        out += "\n## Assertions\n\n"
        for a in record.config.assertions {
            let outcome = record.assertionResults[a.id]?.title ?? "pending"
            out += "- [\(outcome)] \(a.label)\n"
        }

        out += "\n## Timeline\n\n"
        for e in record.events.prefix(200) {
            out += "- **\(Self.timeFormatter.string(from: e.date))** — \(e.message)\n"
        }

        out += "\n## Evidence\n\n"
        var wroteEvidence = false
        for a in record.config.assertions {
            if let ev = record.evidenceByAssertion[a.id] {
                wroteEvidence = true
                out += "- **\(a.label)** (\(record.assertionResults[a.id]?.title.lowercased() ?? "pending"))\n"
                out += "  - Expected: \(ev.expectedDescription)\n"
                out += "  - Observed: \(ev.observed)\n"
                out += "  - \(ev.explanation)\n"
            }
        }
        if !wroteEvidence { out += "- No evidence was recorded for this experiment's assertions.\n" }

        out += "\n## Restoration\n\n"
        if record.restorationStatus.isEmpty {
            out += "- No restoration required.\n"
        } else {
            for (k, ok) in record.restorationStatus.sorted(by: { $0.key < $1.key }) {
                out += "- \(k): \(ok ? "restored ✓ (verified)" : "FAILED ✗ (verification did not pass)")\n"
            }
        }

        out += "\n## Summary\n\n"
        out += Self.honestSummary(for: record)

        return out
    }

    /// A factual summary built ONLY from recorded data. It states what was
    /// injected and what was observed — no causes are inferred (Sections 30/31).
    public static func honestSummary(for record: ExperimentRecord) -> String {
        var lines: [String] = []
        let summary = record.assertionSummary

        lines.append("\(record.config.bindings.count) fault(s) were injected into \(record.config.targets.first?.name ?? "the system") over \(record.duration.map { String(format: "%.1f", $0) } ?? "an unknown") seconds.")

        switch record.outcome {
        case .failed:
            for a in record.config.assertions where record.assertionResults[a.id] == .failed {
                if let ev = record.evidenceByAssertion[a.id], !ev.observed.isEmpty {
                    lines.append("\"\(a.label)\" did not hold: \(ev.observed).")
                } else {
                    lines.append("\"\(a.label)\" did not hold.")
                }
            }
        case .passed:
            lines.append("All \(summary.passed) assertion(s) held while the faults were active.")
        case .stopped:
            lines.append("The experiment was stopped before completion.")
        case .inconclusive:
            lines.append("The experiment ended without enough evidence to reach a conclusion.")
        default:
            break
        }

        let restorationProblems = record.restorationStatus.filter { !$0.value }
        if !restorationProblems.isEmpty {
            lines.append("Restoration could not be verified for: \(restorationProblems.keys.sorted().joined(separator: ", ")).")
        }

        lines.append("This summary states only what Chaos recorded. It does not establish causal relationships.")
        return lines.map { "- \($0)" }.joined(separator: "\n")
    }

    // MARK: JSON

    public static func jsonData(for record: ExperimentRecord) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(record)
    }

    // MARK: CSV

    public static func csv(for record: ExperimentRecord) -> String {
        var out = "timestamp,kind,message\n"
        for e in record.events {
            let msg = e.message.replacingOccurrences(of: "\"", with: "'")
            out += "\(Self.timeFormatter.string(from: e.date)),\(e.kind.rawValue),\"\(msg)\"\n"
        }
        return out
    }

    // MARK: PDF

    /// Renders the report to PDF synchronously via a hidden print operation.
    /// Note: imports AppKit/WebKit here are the one deliberate presentation-layer exception in ChaosKit.
    public static func pdfData(for record: ExperimentRecord) -> Data? {
        let html = htmlDocument(for: record)
        let webView = WebView(frame: NSRect(x: 0, y: 0, width: 640, height: 800))
        webView.mainFrame.loadHTMLString(html, baseURL: nil)

        let deadline = Date().addingTimeInterval(4)
        while webView.isLoading && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.topMargin = 36; printInfo.bottomMargin = 36
        printInfo.leftMargin = 40; printInfo.rightMargin = 40
        printInfo.jobDisposition = .save
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chaos-report-\(UUID().uuidString).pdf")
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = tmpURL

        let op = NSPrintOperation(view: webView, printInfo: printInfo)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.run()
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        return try? Data(contentsOf: tmpURL)
    }

    /// Synchronous HTML for PDF pipelines that prefer file-based output.
    public static func htmlDocument(for record: ExperimentRecord) -> String {
        var out = "<html><head><meta charset='utf-8'><style>"
        out += "body{font-family:-apple-system,Helvetica,sans-serif;margin:32px;color:#1d1d1f}"
        out += "h1{font-size:22px}h2{font-size:15px;margin-top:24px;color:#555}"
        out += "table{border-collapse:collapse;width:100%;font-size:12px}"
        out += "td,th{border:1px solid #ddd;padding:4px 8px;text-align:left}"
        out += ".ok{color:#1a7f37}.bad{color:#c0392b}"
        out += "</style></head><body>"
        out += "<h1>Chaos Report — \(Self.escapeHTML(record.config.name))</h1>"
        out += "<p><b>Result:</b> \(record.outcome.title) &nbsp; <b>Seed:</b> \(record.config.seed) &nbsp; "
        out += "<b>Duration:</b> \(record.duration.map { $0.asClockString } ?? "—")</p>"

        out += "<h2>Faults</h2><table><tr><th>Fault</th><th>Start</th><th>Duration</th></tr>"
        for b in record.config.bindings {
            out += "<tr><td>\(Self.escapeHTML(b.name))</td><td>\(Int(b.startOffset))s</td><td>\(Int(b.duration))s</td></tr>"
        }
        out += "</table>"

        out += "<h2>Assertions</h2><table><tr><th>Assertion</th><th>Result</th></tr>"
        for a in record.config.assertions {
            let res = record.assertionResults[a.id] ?? .pending
            out += "<tr><td>\(Self.escapeHTML(a.label))</td><td class='\(res == .passed ? "ok" : "bad")'>\(res.title)</td></tr>"
        }
        out += "</table>"

        out += "<h2>Timeline</h2><table><tr><th>Time</th><th>Event</th></tr>"
        for e in record.events.prefix(300) {
            out += "<tr><td>\(Self.timeFormatter.string(from: e.date))</td><td>\(Self.escapeHTML(e.message))</td></tr>"
        }
        out += "</table></body></html>"
        return out
    }

    static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    public static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long; f.timeStyle = .short
        return f
    }()

    public static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
