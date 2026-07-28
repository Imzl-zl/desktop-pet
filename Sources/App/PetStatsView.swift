import AppKit
import SwiftUI
import AgentPetCore

/// The pet's right-click HUD: the companion's stats plus a compact footer with
/// Settings / Updates / Quit (the same actions as the menu bar popover).
struct PetStatsView: View {
    /// The pet whose stats to show. `nil` resolves to the globally selected pet
    /// (preserves today's right-click-on-the-single-pet behaviour).
    var petID: String? = nil
    @ObservedObject private var care = PetCareController.shared
    @ObservedObject private var pet = PetController.shared
    @ObservedObject private var imagePets = ImagePetStore.shared
    @ObservedObject private var usage = OpenUsageClient.shared
    @ObservedObject private var usageStore = ProjectUsageStore.shared
    @ObservedObject private var updater = UpdaterController.shared
    @State private var updateLabel: String?
    @State private var hoveredAchievement: Achievement?

    /// The pet id this card is showing — the passed id, else the selected pet.
    private var resolvedPetID: String? { petID ?? pet.selectedPetID }

    private var pack: ImagePetPack? {
        resolvedPetID.flatMap { imagePets.pack(id: $0) }
    }

    /// Care state of the resolved pet.
    private var careState: PetCareState { care.state(for: resolvedPetID) }
    private var level: Int { PetCare.displayLevel(forXP: careState.xp) }
    private var stageKey: String { PetCare.stageName(forLevel: PetCare.level(forXP: careState.xp)) }
    private var stageIndex: Int { PetCare.stageIndex(forLevel: PetCare.level(forXP: careState.xp)) }
    private var levelProgress: Double { PetCare.progress(forXP: careState.xp) }
    private var hunger: PetHunger { PetCare.hunger(state: careState, now: Date()) }

    private var stageColor: Color { Theme.stageColors[min(stageIndex, Theme.stageColors.count - 1)].top }

    var body: some View {
        let state = careState
        VStack(alignment: .leading, spacing: Theme.space3) {
            header(state)
            xpBlock(state)
            achievementBlock
            statGrid(state)
            trendBlock(state)
            costBlock
            usageBlock
            if let last = state.lastFedAt {
                HStack {
                    Text("Last fed")
                        .font(.ui(size: 10))
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                    Text(verbatim: last.formatted(.relative(presentation: .named)))
                        .font(.ui(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            footer
        }
        .padding(Theme.space4)
        .frame(width: 300)
        .background(Theme.background)
        .themedCard(padding: 0, radius: Theme.radiusXl, shadow: true)
        .environment(\.colorScheme, .dark)
        .textSelection(.enabled)
        .noFocusRing()
    }

    // MARK: - Footer (Settings / Updates / Quit)

    private var footer: some View {
        VStack(spacing: Theme.space2) {
            Divider().overlay(Theme.cardStrokeStrong)
            HStack(spacing: Theme.space3) {
                footButton(icon: "gearshape", label: "Settings") {
                    PetWindowController.shared.closeStatsPopover()
                    SettingsWindowController.shared.show()
                }
                footButton(
                    icon: "arrow.triangle.2.circlepath",
                    label: updateLabel ?? NSLocalizedString("Updates", comment: ""),
                    badge: updater.updatePending
                ) {
                    updateLabel = NSLocalizedString("Checking…", comment: "")
                    UpdaterController.shared.checkForUpdates()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { updateLabel = nil }
                }
                Spacer()
                footButton(icon: "power", label: "Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(.top, Theme.space2)
    }

    private func footButton(icon: String, label: String, badge: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.ui(size: 12, weight: .medium))
                    if badge {
                        Circle().fill(Theme.warning).frame(width: 5, height: 5).offset(x: 3, y: -3)
                    }
                }
                Text(verbatim: label)
            }
            .font(.ui(size: 11, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
        }
        .buttonStyle(PillButtonStyle())
    }

    // MARK: - Header

    private func header(_ state: PetCareState) -> some View {
        HStack(spacing: Theme.space3) {
            Group {
                if let frame = pack?.clip(0).first {
                    Image(nsImage: frame).resizable().interpolation(.none).scaledToFit().padding(4)
                } else {
                    Image(systemName: "pawprint.fill")
                        .font(.ui(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .frame(width: 46, height: 46)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .fill(stageColor.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .strokeBorder(stageColor.opacity(0.35), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: Theme.space1) {
                Text(imagePets.displayName(for: resolvedPetID))
                    .font(.ui(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: Theme.space2) {
                    Text(verbatim: "Lv \(level)")
                        .font(.ui(size: 12, weight: .bold))
                        .foregroundStyle(stageColor)
                    StageBadge(stageIndex: stageIndex, size: 16)
                    Text(NSLocalizedString(stageKey, comment: "stage"))
                        .font(.ui(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(stageColor.opacity(0.18)))
                        .foregroundStyle(stageColor)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Theme.space1) {
                Text(hungerText)
                    .font(.ui(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                ProgressView(value: fullness)
                    .tint(fullness > 0.5 ? Theme.success : (fullness > 0.25 ? Theme.warning : Theme.danger))
                    .controlSize(.small)
                    .frame(width: 64)
            }
        }
    }

    // MARK: - XP

    private func xpBlock(_ state: PetCareState) -> some View {
        let (inLevel, span) = PetCare.xpWithinLevel(forXP: state.xp)
        return VStack(alignment: .leading, spacing: Theme.space1) {
            ProgressView(value: levelProgress).tint(stageColor).controlSize(.small)
            HStack {
                Text(verbatim: "\(Self.plain(inLevel)) / \(Self.plain(span)) XP")
                    .font(.ui(size: 10))
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                Text(verbatim: "\(Int((levelProgress * 100).rounded()))%")
                    .font(.ui(size: 10, weight: .semibold))
                    .foregroundStyle(stageColor)
            }
            Text(String(format: NSLocalizedString("≈ %@ tokens to Lv %d", comment: ""),
                        Self.tokenString(PetCare.tokensToNextLevel(state: state)), level + 1))
                .font(.ui(size: 10, weight: .medium))
                .foregroundStyle(stageColor)
        }
    }

    // MARK: - Achievements

    private var achievementBlock: some View {
        let unlocked = care.achievements
        let total = Achievement.allCases.count
        return VStack(alignment: .leading, spacing: Theme.space2) {
            HStack {
                EyebrowLabel("Achievements")
                Spacer()
                Text(verbatim: "\(unlocked.count) / \(total)")
                    .font(.ui(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 2) {
                ForEach(Achievement.allCases, id: \.self) { a in
                    let symbol = PetCare.achievementSymbol(a)
                    let isUnlocked = unlocked.contains(a)
                    Image(systemName: symbol)
                        .font(.ui(size: 11))
                        .foregroundStyle(isUnlocked ? stageColor : Theme.textDisabled)
                        .frame(maxWidth: .infinity, minHeight: 20)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radiusSm)
                                .fill(hoveredAchievement == a ? Theme.cardHover : .clear)
                        )
                        .help(PetCare.achievementDisplayName(a))
                        .onHover { inside in
                            hoveredAchievement = inside ? a : (hoveredAchievement == a ? nil : hoveredAchievement)
                        }
                }
            }
            .frame(maxWidth: .infinity)
            achievementHint(unlocked: unlocked)
        }
        .themedCard(padding: Theme.space3, radius: Theme.radiusMd)
    }

    /// A single line under the badge row: hovering a badge shows its name, how to
    /// unlock it, and whether it's done. Reliable in the floating HUD where the
    /// system `.help` tooltip can be slow or suppressed.
    @ViewBuilder private func achievementHint(unlocked: Set<Achievement>) -> some View {
        HStack(spacing: Theme.space2) {
            if let a = hoveredAchievement {
                let done = unlocked.contains(a)
                Image(systemName: done ? "checkmark.circle.fill" : "lock.fill")
                    .font(.ui(size: 8))
                    .foregroundStyle(done ? stageColor : Theme.textMuted)
                Text(PetCare.achievementDisplayName(a))
                    .font(.ui(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(verbatim: "·")
                    .font(.ui(size: 9))
                    .foregroundStyle(Theme.textMuted)
                Text(PetCare.achievementDescription(a))
                    .font(.ui(size: 9))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
            } else {
                Text("Hover a badge to see how to unlock it")
                    .font(.ui(size: 9))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 12)
    }

    // MARK: - Stat grid

    private func statGrid(_ state: PetCareState) -> some View {
        let cells: [(String, String, String)] = [
            (NSLocalizedString("Today", comment: ""), Self.tokenString(state.tokensToday),
             mealText(state.mealsToday)),
            (NSLocalizedString("Streak", comment: ""), streakValue(state),
             NSLocalizedString("days fed", comment: "")),
            (NSLocalizedString("Lifetime", comment: ""), Self.tokenString(state.totalTokens),
             NSLocalizedString("tokens eaten", comment: "")),
            (NSLocalizedString("Sessions", comment: ""), "\(state.totalMeals)",
             NSLocalizedString("completed", comment: "")),
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.space2), GridItem(.flexible(), spacing: Theme.space2)], spacing: Theme.space2) {
            ForEach(cells, id: \.0) { cell in
                VStack(alignment: .leading, spacing: 1) {
                    Text(cell.0.uppercased())
                        .font(.ui(size: 8, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.textMuted)
                    Text(verbatim: cell.1)
                        .font(.ui(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(verbatim: cell.2)
                        .font(.ui(size: 9))
                        .foregroundStyle(Theme.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.space2)
                .padding(.vertical, Theme.space2)
                .themedCard(padding: 0, radius: Theme.radiusSm, fill: Theme.cardHover, stroke: Theme.cardStroke)
            }
        }
    }

    // MARK: - 7-day trend

    private func trendBlock(_ state: PetCareState) -> some View {
        let series = PetCare.recentDays(state: state, now: Date())
        let peak = max(series.map(\.tokens).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: Theme.space2) {
            HStack {
                EyebrowLabel("Burn, last 7 days")
                Spacer()
                Text(verbatim: Self.tokenString(series.map(\.tokens).reduce(0, +)))
                    .font(.ui(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(alignment: .bottom, spacing: Theme.space2) {
                ForEach(Array(series.enumerated()), id: \.offset) { i, day in
                    VStack(spacing: Theme.space1) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(i == series.count - 1 ? stageColor : stageColor.opacity(0.4))
                            .frame(height: max(3, CGFloat(day.tokens) / CGFloat(peak) * 34))
                            .frame(maxWidth: .infinity)
                        Text(verbatim: day.label)
                            .font(.ui(size: 8))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
            }
            .frame(height: 48, alignment: .bottom)
        }
        .themedCard(padding: Theme.space3, radius: Theme.radiusMd)
    }

    // MARK: - Cost

    private var costBlock: some View {
        HStack {
            EyebrowLabel("Est. cost (Claude)")
            Spacer()
            Text(verbatim: String(format: NSLocalizedString("Today %@ · Month %@", comment: "cost row: today / this month estimate"),
                                   Self.costString(usageStore.todayCostUSD), Self.costString(usageStore.monthlyCostUSD)))
                .font(.ui(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private static func costString(_ usd: Double) -> String {
        String(format: "$%.2f", usd)
    }

    // MARK: - Usage / limits

    @ObservedObject private var probe = NativeUsageProbe.shared

    @ViewBuilder private var usageBlock: some View {
        let providers = NativeUsageProbe.combined()
        if !providers.isEmpty {
            VStack(alignment: .leading, spacing: Theme.space2) {
                EyebrowLabel("Limits")
                ForEach(providers) { p in
                    let used = 1 - (p.fractionLeft ?? 0)
                    let color: Color = used > 0.9 ? Theme.danger : (used > 0.75 ? Theme.warning : stageColor)
                    VStack(alignment: .leading, spacing: Theme.space1) {
                        HStack(spacing: Theme.space2) {
                            Text(verbatim: p.displayName)
                                .font(.ui(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                            if let w = p.windowLabel {
                                Text(verbatim: w).font(.ui(size: 9)).foregroundStyle(Theme.textMuted)
                            }
                            Spacer()
                            Text(String(format: NSLocalizedString("%d%% used", comment: ""), Int((used * 100).rounded())))
                                .font(.ui(size: 10, weight: .semibold))
                                .foregroundStyle(color)
                            if let reset = Self.resetText(p.resetsAt) {
                                Text(verbatim: "· \(reset)").font(.ui(size: 9)).foregroundStyle(Theme.textMuted)
                            }
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.cardStrokeStrong)
                                Capsule().fill(color).frame(width: max(2, geo.size.width * used))
                            }
                        }
                        .frame(height: 5)
                    }
                }
            }
            .themedCard(padding: Theme.space3, radius: Theme.radiusMd)
        }
    }

    /// "resets in 3h" / "in 12m" from a reset timestamp.
    static func resetText(_ date: Date?) -> String? {
        guard let date else { return nil }
        let secs = date.timeIntervalSinceNow
        guard secs > 0 else { return nil }
        if secs >= 86400 { return String(format: NSLocalizedString("resets in %dd", comment: ""), Int(secs / 86400)) }
        if secs >= 3600 { return String(format: NSLocalizedString("resets in %dh", comment: ""), Int(secs / 3600)) }
        return String(format: NSLocalizedString("resets in %dm", comment: ""), max(1, Int(secs / 60)))
    }

    // MARK: - Derived

    /// Continuous fullness 0…1 (48h since the last feeding → empty).
    private var fullness: Double {
        guard let last = careState.lastFedAt else { return 0.5 }
        let hours = Date().timeIntervalSince(last) / 3600
        return max(0, min(1, 1 - hours / 48))
    }

    private func mealText(_ meals: Int) -> String {
        meals == 1
            ? NSLocalizedString("1 meal", comment: "")
            : String(format: NSLocalizedString("%d meals", comment: ""), meals)
    }

    private func streakValue(_ s: PetCareState) -> String {
        "\(s.streakDays)"
    }

    private var hungerText: String {
        switch hunger {
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
