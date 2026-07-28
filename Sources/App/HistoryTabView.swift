import SwiftUI
import AgentPetCore

struct HistoryTabView: View {
    enum Filter: String, CaseIterable {
        case today = "Today"
        case week = "Past 7 Days"
        case month = "Past 30 Days"
    }

    @State private var filter: Filter = .today
    @State private var records: [SessionArchive] = []

    var body: some View {
        Form {
            Section {
                Picker("Period", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if records.isEmpty {
                Section {
                    HStack(spacing: Theme.space2) {
                        Spacer()
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.ui(size: 24))
                            .foregroundStyle(Theme.textMuted)
                        VStack(alignment: .leading, spacing: Theme.space1) {
                            Text("No sessions yet")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(Theme.textSecondary)
                            Text("Your agent sessions will appear here once they finish.")
                                .font(.caption)
                                .foregroundStyle(Theme.textMuted)
                        }
                        Spacer()
                    }
                    .padding(.vertical, Theme.space4)
                }
            } else {
                Section {
                    SummaryBar(records: records)
                }
                ForEach(groupedByDay, id: \.0) { day, dayRecords in
                    Section(header: DaySectionHeader(date: day, count: dayRecords.count)) {
                        ForEach(dayRecords, id: \.sessionId) { record in
                            SessionRow(record: record)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task(id: filter) {
            await loadRecords()
        }
    }

    // MARK: - Helpers

    private var groupedByDay: [(Date, [SessionArchive])] {
        let cal = Calendar.current
        var dict: [Date: [SessionArchive]] = [:]
        for record in records {
            let day = cal.startOfDay(for: record.startedAt)
            dict[day, default: []].append(record)
        }
        return dict.keys
            .sorted(by: >)
            .map { day in (day, dict[day]!.sorted { $0.startedAt > $1.startedAt }) }
    }

    private func loadRecords() async {
        let store = SessionArchiveStore.shared
        let now = Date()
        let since: Date?
        switch filter {
        case .today:
            since = nil
        case .week:
            since = Calendar.current.date(byAdding: .day, value: -6, to: now)
        case .month:
            since = Calendar.current.date(byAdding: .day, value: -29, to: now)
        }
        let fetched: [SessionArchive]
        if let since {
            fetched = await Task.detached { store.allRecords(since: since) }.value
        } else {
            fetched = await Task.detached { store.records(for: now) }.value
        }
        records = fetched.sorted { $0.startedAt > $1.startedAt }
    }
}

// MARK: - Summary Bar

private struct SummaryBar: View {
    let records: [SessionArchive]

    private var totalDuration: TimeInterval { records.reduce(0) { $0 + $1.duration } }

    private var kindCounts: [(AgentKind, Int)] {
        var dict: [AgentKind: Int] = [:]
        for r in records { dict[r.agentKind, default: 0] += 1 }
        return dict.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            HStack(spacing: Theme.space4) {
                summaryPill(icon: "clock.arrow.circlepath", text: "\(records.count) sessions")
                summaryPill(icon: "timer", text: formatBarDuration(totalDuration))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.space2) {
                    ForEach(kindCounts, id: \.0.rawValue) { kind, count in
                        KindChip(kind: kind, count: count)
                    }
                }
            }
        }
        .padding(.vertical, Theme.space1)
    }

    private func summaryPill(icon: String, text: String) -> some View {
        HStack(spacing: Theme.space1) {
            Image(systemName: icon)
                .font(.ui(size: 11))
                .foregroundStyle(Theme.textMuted)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, Theme.space2)
        .padding(.vertical, Theme.space1)
        .themedCard(padding: 0, radius: Theme.radiusMd, fill: Theme.cardHover, stroke: Theme.cardStroke)
    }
}

private struct KindChip: View {
    let kind: AgentKind
    let count: Int

    var body: some View {
        HStack(spacing: Theme.space1) {
            Image(systemName: sfSymbol(for: kind))
                .font(.ui(size: 10))
            Text("\(kind.rawValue) ×\(count)")
                .font(.caption2)
        }
        .padding(.horizontal, Theme.space2)
        .padding(.vertical, Theme.space1)
        .background(Capsule().fill(Theme.accentSoft))
        .foregroundStyle(Theme.accent)
    }
}

// MARK: - Section Header

private struct DaySectionHeader: View {
    let date: Date
    let count: Int

    var body: some View {
        HStack {
            Text(date, style: .date)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("\(count) session\(count == 1 ? "" : "s")")
                .foregroundStyle(Theme.textMuted)
        }
        .font(.caption)
    }
}

// MARK: - Row

private struct SessionRow: View {
    let record: SessionArchive

    private var displayTitle: String {
        if let t = record.title, !t.isEmpty { return t }
        if let m = record.message, !m.isEmpty { return String(m.prefix(50)) }
        return record.sessionId
    }

    var body: some View {
        HStack(spacing: Theme.space3) {
            Image(systemName: sfSymbol(for: record.agentKind))
                .font(.ui(size: 16))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                        .fill(Theme.accentSoft)
                )
                .foregroundStyle(Theme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.callout)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let project = record.project, !project.isEmpty {
                    Text(project)
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatRowDuration(record.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                if let tokens = record.tokenCount {
                    Text("\(tokens)t")
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                }
            }
        }
        .padding(.vertical, Theme.space1)
    }
}

// MARK: - Helpers

private func formatBarDuration(_ interval: TimeInterval) -> String {
    let h = Int(interval) / 3600
    let m = (Int(interval) % 3600) / 60
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}

private func formatRowDuration(_ interval: TimeInterval) -> String {
    let h = Int(interval) / 3600
    let m = (Int(interval) % 3600) / 60
    let s = Int(interval) % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: "%d:%02d", m, s)
}

// MARK: - SF Symbol mapping

private func sfSymbol(for kind: AgentKind) -> String {
    switch kind {
    case .claude:      return "a.circle.fill"
    case .codex:       return "gearshape.fill"
    case .gemini:      return "sparkle"
    case .cursor:      return "cursorarrow"
    case .opencode:    return "chevron.left.forwardslash.chevron.right"
    case .windsurf:    return "wind"
    case .antigravity: return "arrow.up.circle.fill"
    case .copilot:     return "airplane"
    case .kiroCLI:     return "k.circle.fill"
    case .droid:       return "cpu.fill"
    case .pi:          return "pi"
    case .cli:         return "terminal.fill"
    case .unknown:     return "questionmark.circle"
    }
}
