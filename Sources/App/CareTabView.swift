import SwiftUI
import AgentPetCore

/// The tamagotchi panel: level + evolution stage, hunger, today's feeding,
/// lifetime totals, and where the food data comes from.
struct CareTabView: View {
    @ObservedObject private var care = PetCareController.shared
    @ObservedObject private var usage = OpenUsageClient.shared
    @ObservedObject private var probe = NativeUsageProbe.shared
    @ObservedObject private var sync = CareSyncController.shared
    @ObservedObject private var pet = PetController.shared
    @ObservedObject private var imagePets = ImagePetStore.shared
    @Environment(\.openURL) private var openURL

    /// Ticks so hunger and "today" counters stay fresh while the panel is open.
    @State private var now = Date()
    /// Transient result of a manual cloud restore.
    @State private var restoreNote: String?
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var currentPack: ImagePetPack? {
        pet.selectedPetID.flatMap { imagePets.pack(id: $0) }
    }

    private var currentName: String {
        imagePets.displayName(for: pet.selectedPetID)
    }

    var body: some View {
        Form {
            Section("Companion") {
                companionCard
            }

            Section("Hunger") {
                hungerCard
            }

            Section("Today") {
                LabeledContent("Tokens eaten") {
                    Text(verbatim: Self.plain(care.current.tokensToday))
                        .foregroundStyle(Theme.textPrimary)
                }
                LabeledContent("Sessions finished", value: "\(care.current.mealsToday)")
                LabeledContent("Streak") {
                    Text(care.current.streakDays == 1
                         ? NSLocalizedString("1 day", comment: "streak singular")
                         : String(format: NSLocalizedString("%d days", comment: "streak"), care.current.streakDays))
                    .foregroundStyle(Theme.textPrimary)
                }
            }

            Section("Lifetime") {
                LabeledContent("Total tokens eaten", value: Self.plain(care.current.totalTokens))
                LabeledContent("Total sessions", value: "\(care.current.totalMeals)")
            }

            Section {
                achievementsGrid
                    .padding(.vertical, Theme.space1)
            } header: {
                Text("Achievements")
            } footer: {
                Text(verbatim: "\(care.achievements.count) of \(Achievement.allCases.count) unlocked")
                    .foregroundStyle(Theme.textMuted)
            }

            if care.raisedPetIDs.count > 1 {
                Section("All companions") {
                    ForEach(care.raisedPetIDs, id: \.self) { id in
                        companionRow(id: id)
                    }
                    Text("Each companion keeps its own experience. Switch pets in the Pet tab to raise another one.")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                }
            }

            syncSection

            Section("Food sources") {
                foodSourceRow(
                    title: "Claude Code transcripts",
                    detail: "Token usage is read locally when a turn ends.",
                    isActive: true
                )
                foodSourceRow(
                    title: "Subscription limits",
                    detail: probe.providers.isEmpty
                         ? "Read directly from your Claude Code / Codex sign-ins. None found yet."
                         : "Read directly from your Claude Code / Codex sign-ins.",
                    isActive: !probe.providers.isEmpty
                )
                ForEach(NativeUsageProbe.combined()) { p in
                    usageRow(p: p)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            care.refreshDay()
            probe.poll()
            usage.poll()
        }
        .onReceive(tick) { date in
            now = date
            care.refreshDay()
        }
    }

    // MARK: - Companion hero

    private var companionCard: some View {
        HStack(spacing: Theme.space3) {
            Group {
                if let frame = currentPack?.clip(0).first {
                    Image(nsImage: frame).resizable().interpolation(.none).scaledToFit()
                        .padding(5)
                } else {
                    Image(systemName: stageIcon)
                        .font(.ui(size: 22, weight: .semibold))
                        .foregroundStyle(stageColor)
                }
            }
            .frame(width: 52, height: 52)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .fill(stageColor.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .strokeBorder(stageColor.opacity(0.35), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: Theme.space1) {
                HStack(spacing: Theme.space2) {
                    Text(verbatim: currentName)
                        .font(.title3).bold()
                        .foregroundStyle(Theme.textPrimary)
                    Text(verbatim: "Lv \(care.level)")
                        .font(.title3)
                        .foregroundStyle(stageColor)
                    StageBadge(stageIndex: care.stageIndex, size: 22)
                    Text(NSLocalizedString(care.stageKey, comment: "evolution stage"))
                        .font(.caption).bold()
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(stageColor.opacity(0.18)))
                        .foregroundStyle(stageColor)
                }
                ProgressView(value: care.levelProgress)
                    .tint(stageColor)
                Text(xpCaption)
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
                Text(String(format: NSLocalizedString("≈ %@ tokens to Lv %d", comment: ""),
                            Self.tokenString(PetCare.tokensToNextLevel(state: care.current)),
                            care.level + 1))
                    .font(.caption)
                    .foregroundStyle(stageColor)
            }
        }
        .padding(.vertical, Theme.space1)
    }

    // MARK: - Hunger

    private var hungerCard: some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            HStack {
                Text(hungerLabel)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let last = care.current.lastFedAt {
                    Text(String(format: NSLocalizedString("Last fed %@", comment: ""),
                                last.formatted(.relative(presentation: .named))))
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            ProgressView(value: fullness)
                .tint(fullness > 0.5 ? Theme.success : (fullness > 0.25 ? Theme.warning : Theme.danger))
            Text("The pet eats real work: tokens burnt by your agents and finished sessions.")
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.vertical, Theme.space1)
    }

    // MARK: - Achievements

    private var achievementsGrid: some View {
        let unlocked = care.achievements
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.space2), count: 5), spacing: 14) {
            ForEach(Achievement.allCases, id: \.self) { a in
                let on = unlocked.contains(a)
                VStack(spacing: Theme.space1) {
                    Image(systemName: PetCare.achievementSymbol(a))
                        .font(.ui(size: 18))
                        .foregroundStyle(on ? stageColor : Theme.textDisabled)
                        .frame(height: 22)
                    Text(PetCare.achievementDisplayName(a))
                        .font(.ui(size: 9))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(on ? Theme.textPrimary : Theme.textMuted)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
                .opacity(on ? 1 : 0.5)
                .help("\(PetCare.achievementDisplayName(a)) — \(PetCare.achievementDescription(a))")
            }
        }
    }

    // MARK: - Sync

    private var syncSection: some View {
        Section {
            if sync.linked {
                HStack(spacing: Theme.space3) {
                    VStack(alignment: .leading, spacing: Theme.space1) {
                        if let login = sync.linkedLogin, !login.isEmpty {
                            Text(String(format: NSLocalizedString("Connected as %@", comment: ""), login))
                                .foregroundStyle(Theme.textPrimary)
                        } else {
                            Text("Connected to your profile")
                                .foregroundStyle(Theme.textPrimary)
                        }
                        if let note = restoreNote {
                            Text(note).font(.caption).foregroundStyle(Theme.textMuted)
                        } else if let at = sync.lastSyncAt {
                            Text(String(format: NSLocalizedString("Last synced %@", comment: ""),
                                        at.formatted(.relative(presentation: .named))))
                                .font(.caption)
                                .foregroundStyle(Theme.textMuted)
                        } else {
                            Text("Your companions appear on your profile page.")
                                .font(.caption)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    Spacer()
                    HStack(spacing: Theme.space2) {
                        Button("Restore") {
                            restoreNote = NSLocalizedString("Restoring…", comment: "")
                            Task {
                                let n = await sync.restore(manual: true)
                                restoreNote = n > 0
                                    ? String(format: NSLocalizedString("Restored %d pet(s) from the cloud.", comment: ""), n)
                                    : NSLocalizedString("Already up to date.", comment: "")
                            }
                        }
                        .buttonStyle(BorderedButtonStyle())
                        .disabled(sync.restoring)

                        Button("Open profile") {
                            openURL(URL(string: "https://agentpet.thenightwatcher.online/profile")!)
                        }
                        .buttonStyle(BorderedButtonStyle())

                        Button("Disconnect") { sync.disconnect() }
                            .buttonStyle(BorderedButtonStyle())
                    }
                }
            } else {
                HStack(spacing: Theme.space3) {
                    VStack(alignment: .leading, spacing: Theme.space1) {
                        Text("Show your companions on your web profile")
                            .foregroundStyle(Theme.textPrimary)
                        Text("Your browser opens GitHub sign-in; the app links automatically.")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                        if let err = sync.lastError {
                            Text(err).font(.caption).foregroundStyle(Theme.danger)
                        }
                    }
                    Spacer()
                    Button {
                        sync.beginLink()
                    } label: {
                        Label("Sign in with GitHub", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .buttonStyle(AccentButtonStyle())
                }
            }
        } header: {
            Text("Web profile")
        } footer: {
            Text("Connecting is optional. Your pet, its level and all stats live on this Mac whether or not you sign in, nothing leaves your machine until you connect.")
                .foregroundStyle(Theme.textMuted)
        }
    }

    // MARK: - Food sources helpers

    private func foodSourceRow(title: String, detail: String, isActive: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.space1) {
                Text(title)
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            if isActive {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .bold()
                    .foregroundStyle(Theme.success)
            }
        }
    }

    private func usageRow(p: NativeUsageProvider) -> some View {
        let used = 1 - (p.fractionLeft ?? 0)
        let color: Color = used > 0.9 ? Theme.danger : (used > 0.75 ? Theme.warning : stageColor)
        return VStack(alignment: .leading, spacing: Theme.space1) {
            HStack(spacing: Theme.space2) {
                Text(verbatim: p.displayName)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                if let w = p.windowLabel {
                    Text(verbatim: w).font(.caption).foregroundStyle(Theme.textMuted)
                }
                Spacer()
                Text(String(format: NSLocalizedString("%d%% used", comment: ""), Int((used * 100).rounded())))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                if let reset = PetStatsView.resetText(p.resetsAt) {
                    Text(verbatim: "· \(reset)").font(.caption).foregroundStyle(Theme.textMuted)
                }
            }
            ProgressView(value: used).tint(color)
        }
        .padding(.vertical, Theme.space1)
    }

    // MARK: - Companions

    @ViewBuilder
    private func companionRow(id: String) -> some View {
        let s = care.state(for: id)
        let lv = PetCare.displayLevel(forXP: s.xp)
        let idx = PetCare.stageIndex(forLevel: PetCare.level(forXP: s.xp))
        let color = Theme.stageColors[min(idx, Theme.stageColors.count - 1)].top
        HStack(spacing: Theme.space3) {
            Group {
                if let frame = imagePets.pack(id: id)?.clip(0).first {
                    Image(nsImage: frame).resizable().interpolation(.none).scaledToFit()
                } else {
                    Image(systemName: Theme.stageColors[min(idx, Theme.stageColors.count - 1)].glyph)
                        .font(.ui(size: 13))
                        .foregroundStyle(color)
                }
            }
            .frame(width: 24, height: 24)
            .overlay(alignment: .bottomTrailing) {
                StageBadge(stageIndex: idx, size: 13).offset(x: 3, y: 3)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.space2) {
                    Text(verbatim: imagePets.displayName(for: id))
                        .font(.ui(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if id == care.currentPetID {
                        Text("Raising")
                            .font(.caption2).bold()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.accentSoft))
                            .foregroundStyle(Theme.accent)
                    }
                }
                ProgressView(value: PetCare.progress(forXP: s.xp))
                    .tint(color)
                    .controlSize(.small)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: "Lv \(lv)")
                    .font(.ui(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(verbatim: "\(Self.plain(s.xp)) XP")
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.vertical, Theme.space1)
    }

    // MARK: - Derived display

    private var stageIcon: String { Theme.stageColors[min(care.stageIndex, Theme.stageColors.count - 1)].glyph }
    private var stageColor: Color { Theme.stageColors[min(care.stageIndex, Theme.stageColors.count - 1)].top }

    private var xpCaption: String {
        let (inLevel, span) = PetCare.xpWithinLevel(forXP: care.current.xp)
        return String(format: NSLocalizedString("%@ / %@ XP to next level", comment: ""),
                      Self.plain(inLevel), Self.plain(span))
    }

    /// Continuous fullness 0…1 from the time since the last feeding (48h → empty).
    private var fullness: Double {
        guard let last = care.current.lastFedAt else { return 0.5 }
        let hours = now.timeIntervalSince(last) / 3600
        return max(0, min(1, 1 - hours / 48))
    }

    private var hungerLabel: String {
        switch care.hunger {
        case .full: return NSLocalizedString("Full", comment: "hunger")
        case .satisfied: return NSLocalizedString("Satisfied", comment: "hunger")
        case .peckish: return NSLocalizedString("Peckish", comment: "hunger")
        case .hungry: return NSLocalizedString("Hungry", comment: "hunger")
        case .starving: return NSLocalizedString("Starving", comment: "hunger")
        }
    }

    private static func tokenString(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.0fk", Double(n) / 1_000)
        default: return "\(n)"
        }
    }

    private static func plain(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
