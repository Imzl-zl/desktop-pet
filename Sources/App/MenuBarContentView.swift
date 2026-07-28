import SwiftUI
import AppKit
import AgentPetCore

/// Rich menu bar popover: a blurred dark card with an arrow pointing at the
/// status item, a live agent list, and a footer bar.
struct MenuContentView: View {
    @ObservedObject private var daemon = AppDaemon.shared
    @ObservedObject private var petWindow = PetWindowController.shared
    @ObservedObject private var statusBar = StatusBarController.shared
    @ObservedObject private var pet = PetController.shared
    var dismiss: () -> Void

    /// Show agents that are doing something or just finished. Idle and merely
    /// `registered` (open but not working) sessions are hidden, so an idle
    /// terminal doesn't sit in the list; they reappear the moment they work.
    private var agents: [AgentSession] {
        daemon.sessions.filter { $0.state != .idle && $0.state != .registered }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            careSection
            divider
            agentSection
            divider
            controls
            divider
            footer
        }
        .frame(width: 300)
        .background(Theme.background)
        .themedCard(padding: 0, radius: Theme.radiusXl, shadow: true)
        .environment(\.colorScheme, .dark)
        .noFocusRing()
    }

    private var divider: some View { Divider().overlay(Theme.cardStrokeStrong) }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.space3) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                    .fill(Theme.accent)
                Image(systemName: "pawprint.fill")
                    .font(.ui(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 28, height: 28)
            .shadow(color: Theme.accentGlow, radius: 8, y: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text("AgentPet")
                    .font(.ui(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.ui(size: 11))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
        }
        .padding(Theme.space4)
    }

    private var subtitle: String {
        let total = agents.count
        if total == 0 { return "No agents running" }
        let running = agents.filter { $0.state == .working }.count
        let label = "\(total) agent\(total == 1 ? "" : "s")"
        return running > 0 ? "\(label) · \(running) running" : label
    }

    // MARK: Companion (care stats)

    @ObservedObject private var care = PetCareController.shared
    @ObservedObject private var imagePets = ImagePetStore.shared

    private var careSection: some View {
        let state = care.current
        let level = care.level
        let idx = min(care.stageIndex, Theme.stageColors.count - 1)
        let color = Theme.stageColors[idx].top
        let name = imagePets.displayName(for: pet.selectedPetID)

        return VStack(alignment: .leading, spacing: Theme.space2) {
            EyebrowLabel("Companion")
                .padding(.horizontal, Theme.space4)
                .padding(.top, Theme.space3)
                .padding(.bottom, Theme.space1)

            HStack(spacing: Theme.space2) {
                StageBadge(stageIndex: idx, size: 20)
                Text(name)
                    .font(.ui(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).truncationMode(.tail)
                Text(verbatim: "Lv \(level)")
                    .font(.ui(size: 12, weight: .bold))
                    .foregroundStyle(color)
                    .layoutPriority(1)
                Spacer(minLength: Theme.space2)
                Text(hungerText)
                    .font(.ui(size: 11))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1).layoutPriority(1)
            }
            .padding(.horizontal, Theme.space4)

            ProgressView(value: care.levelProgress)
                .tint(color)
                .controlSize(.small)
                .padding(.horizontal, Theme.space4)

            HStack {
                Text(verbatim: xpLine)
                Spacer()
                Text(verbatim: todayLine)
            }
            .font(.ui(size: 10))
            .foregroundStyle(Theme.textMuted)
            .padding(.horizontal, Theme.space4)
            .padding(.bottom, Theme.space3)
        }
    }

    private var xpLine: String {
        let (inLevel, span) = PetCare.xpWithinLevel(forXP: care.current.xp)
        return "\(inLevel) / \(span) XP"
    }

    private var todayLine: String {
        let tokens = care.current.tokensToday
        let label = tokens >= 1_000_000 ? String(format: "%.1fM", Double(tokens) / 1_000_000)
            : tokens >= 1_000 ? String(format: "%.0fk", Double(tokens) / 1_000) : "\(tokens)"
        if care.current.mealsToday == 1 {
            return String(format: NSLocalizedString("Today %@ tokens · 1 meal", comment: "popover care today line, singular"), label)
        }
        return String(
            format: NSLocalizedString("Today %@ tokens · %d meals", comment: "popover care today line"),
            label, care.current.mealsToday
        )
    }

    private var hungerText: String {
        switch care.hunger {
        case .full: return NSLocalizedString("Full", comment: "hunger")
        case .satisfied: return NSLocalizedString("Satisfied", comment: "hunger")
        case .peckish: return NSLocalizedString("Peckish", comment: "hunger")
        case .hungry: return NSLocalizedString("Hungry", comment: "hunger")
        case .starving: return NSLocalizedString("Starving", comment: "hunger")
        }
    }

    // MARK: Agents

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                EyebrowLabel("Agents")
                    .padding(.horizontal, Theme.space4)
                    .padding(.top, Theme.space3)
                    .padding(.bottom, Theme.space1)
                Spacer()
                if !agents.isEmpty {
                    Button("Clear all") { daemon.clearSessions() }
                        .buttonStyle(.plain)
                        .font(.ui(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textMuted)
                        .padding(.trailing, Theme.space4)
                        .padding(.top, Theme.space3)
                        .padding(.bottom, Theme.space1)
                }
            }
            if agents.isEmpty {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: Theme.space1) {
                        Text("Nothing running right now.")
                            .font(.ui(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        Text(IdleBoost.line(at: context.date))
                            .font(.ui(size: 12))
                            .foregroundStyle(Theme.textMuted)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, Theme.space4)
                    .padding(.bottom, Theme.space3)
                }
            } else {
                ForEach(agents) { session in
                    AgentRow(session: session, onClear: { daemon.removeSession(session.id) })
                }
                .padding(.bottom, Theme.space2)
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 0) {
            controlRow(icon: "pawprint", label: "Show pet", isOn: $petWindow.isVisible)
            controlRow(icon: "number", label: "Show count on menu bar", isOn: $statusBar.showCount)
            controlRow(icon: "bubble.left", label: "Show chat on menu bar", isOn: $statusBar.showChatOnMenuBar)
            controlRow(icon: "list.bullet.rectangle", label: "Show bubble on menu bar", isOn: $statusBar.showBubbleOnMenuBar)
            controlRow(icon: "square.split.2x1", label: "Split pet", isOn: $pet.splitPet)
            animationRow
            sizeRow
        }
    }

    private var animationRow: some View {
        HStack(spacing: Theme.space2) {
            Image(systemName: "play.fill")
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 16)
            Text("Animate pets")
                .font(.ui(size: 13))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if pet.animationsEnabled {
                HStack(spacing: Theme.space1) {
                    Slider(value: $pet.animationFPS, in: 1...12, step: 1)
                        .controlSize(.mini)
                        .tint(Theme.accent)
                        .frame(width: 80)
                    Text("\(Int(pet.animationFPS))")
                        .font(.ui(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize()
                }
            }
            ColorSwitch(isOn: $pet.animationsEnabled)
        }
        .padding(.horizontal, Theme.space4)
        .padding(.vertical, Theme.space2)
        .animation(Theme.easeMedium, value: pet.animationsEnabled)
    }

    private var sizeRow: some View {
        HStack(spacing: Theme.space2) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 16)
            Text("Pet size")
                .font(.ui(size: 13))
                .foregroundStyle(Theme.textPrimary)
            Slider(value: $pet.petPoint, in: PetController.minPoint...PetController.maxPoint)
                .controlSize(.mini)
                .tint(Theme.accent)
        }
        .padding(.horizontal, Theme.space4)
        .padding(.vertical, Theme.space2)
    }

    private func controlRow(icon: String, label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: Theme.space2) {
            Image(systemName: icon)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 16)
            Text(label)
                .font(.ui(size: 13))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            ColorSwitch(isOn: isOn)
        }
        .padding(.horizontal, Theme.space4)
        .padding(.vertical, Theme.space2)
    }

    // MARK: Footer

    @ObservedObject private var updater = UpdaterController.shared

    private var footer: some View {
        HStack(spacing: Theme.space3) {
            FooterButton(icon: "gearshape", label: "Settings") {
                StatusBarController.shared.closeAndThen {
                    SettingsWindowController.shared.show()
                }
            }
            FooterButton(
                icon: "arrow.triangle.2.circlepath",
                label: "Updates",
                badge: updater.updatePending
            ) {
                StatusBarController.shared.closeAndThen {
                    UpdaterController.shared.checkForUpdates()
                }
            }
            Spacer()
            FooterButton(icon: "power", label: "Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, Theme.space4)
        .padding(.vertical, Theme.space3)
    }
}

// MARK: - Menu bar hanging bubble

/// Thin wrapper so the agent bubble shown below the menu bar icon
/// auto-refreshes via @ObservedObject without re-creating the NSPanel.
struct MenuBarBubbleView: View {
    @ObservedObject private var pet = PetController.shared

    var body: some View {
        AgentBubble(sessions: pet.activeAgentSessions, tailEdge: .top)
            .environment(\.colorScheme, .dark)
    }
}

private struct FooterButton: View {
    let icon: String
    let label: String
    var badge: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.ui(size: 13, weight: .medium))
                    if badge {
                        Circle()
                            .fill(Theme.warning)
                            .frame(width: 6, height: 6)
                            .offset(x: 4, y: -4)
                    }
                }
                Text(label)
            }
            .font(.ui(size: 12, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
        }
        .buttonStyle(PillButtonStyle())
    }
}

private struct AgentRow: View {
    let session: AgentSession
    var onClear: () -> Void = {}
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.space3) {
            Circle().fill(dotColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(project)
                    .font(.ui(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.ui(size: 11))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: Theme.space2)
            if hovering {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textMuted)
                }
                .buttonStyle(.plain)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(timeString(now: context.date))
                        .font(.ui(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                }
            }
        }
        .padding(.horizontal, Theme.space4)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(hovering ? Theme.cardHover : .clear)
        .animation(Theme.easeFast, value: hovering)
        .onHover { hovering = $0 }
    }

    private var project: String {
        session.project.map { ($0 as NSString).lastPathComponent } ?? session.id
    }

    /// The agent's context (waiting reason / running tool) when known, else its state.
    private var subtitle: String {
        if let message = session.message, !message.isEmpty { return message }
        return session.state.rawValue.capitalized
    }

    private var dotColor: Color {
        switch session.state {
        case .working, .registered: return Theme.info
        case .waiting: return Theme.warning
        case .done: return Theme.success
        case .idle: return Theme.textMuted
        }
    }

    private func timeString(now: Date) -> String {
        switch session.state {
        case .done, .idle:
            return session.updatedAt.formatted(date: .omitted, time: .shortened)
        default:
            let s = max(0, Int(now.timeIntervalSince(session.stateSince)))
            return s < 60 ? "\(s)s" : "\(s / 60)m \(s % 60)s"
        }
    }
}
