import SwiftUI
import DesktopPetCore

/// Native macOS-style settings: a preferences-style toolbar of tabs over
/// grouped forms (dark).
struct SetupView: View {
    @ObservedObject private var model = SettingsModel.shared
    @ObservedObject private var pet = PetController.shared
    @ObservedObject private var imagePets = ImagePetStore.shared
    @ObservedObject private var appLang = AppLanguage.shared
    var onClose: () -> Void
    /// Asks the window to resize to a target content width so the live-preview
    /// panel can slide in on the right. Provided by SettingsWindowController.
    var onResize: (CGFloat) -> Void = { _ in }

    enum Tab { case pet, bubble, care, general, advanced }
    @State private var tab: Tab = .pet
    @State private var demoOpen = false

    private let baseWidth: CGFloat = 640
    private let demoWidth: CGFloat = 740

    private var selectedPack: ImagePetPack? {
        pet.selectedPetID.flatMap { imagePets.pack(id: $0) }
    }

    private func setDemo(_ open: Bool) {
        demoOpen = open
        onResize(open ? baseWidth + demoWidth : baseWidth)
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsColumn.frame(width: baseWidth)
            if demoOpen {
                Divider().overlay(Theme.cardStrokeStrong)
                SettingsDemoPanel(onClose: { setDemo(false) }).frame(width: demoWidth)
            }
        }
        .frame(width: demoOpen ? baseWidth + demoWidth : baseWidth, height: 600)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .noFocusRing()
        .environment(\.locale, appLang.locale)
        .id(appLang.lang.rawValue)
        .onAppear { model.refresh() }
    }

    private var settingsColumn: some View {
        VStack(spacing: 0) {
            tabBar
            Divider().overlay(Theme.cardStrokeStrong)
            Group {
                switch tab {
                case .general:
                    GeneralTab(model: model, pet: pet)
                case .pet:
                    PetTab(pet: pet, imagePets: imagePets, model: model, selectedPack: selectedPack)
                case .care:
                    CareTabView()
                case .bubble:
                    BubbleSettingsView()
                case .advanced:
                    AdvancedTab(model: model)
                }
            }
            .frame(maxHeight: .infinity)
            Divider().overlay(Theme.cardStrokeStrong)
            bottomBar
        }
    }

    private var bottomBar: some View {
        HStack(spacing: Theme.space3) {
            Button { setDemo(!demoOpen) } label: {
                Label(demoOpen ? "Hide live preview" : "Live preview", systemImage: "sparkles.tv")
            }
            .buttonStyle(AccentButtonStyle())
            Text("Preview your pet and bubble settings with live samples.")
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, Theme.space4)
        .padding(.vertical, Theme.space3)
        .background(Theme.card.opacity(0.5))
    }

    private var tabBar: some View {
        HStack(spacing: Theme.space2) {
            TabButton(icon: "pawprint.fill", label: "Pet", selected: tab == .pet) { tab = .pet }
            TabButton(icon: "bubble.left.and.bubble.right.fill", label: "Bubble", selected: tab == .bubble) { tab = .bubble }
            TabButton(icon: "fork.knife", label: "Care", selected: tab == .care) { tab = .care }
            TabButton(icon: "gearshape.fill", label: "General", selected: tab == .general) { tab = .general }
            TabButton(icon: "wrench.and.screwdriver.fill", label: "Advanced", selected: tab == .advanced) { tab = .advanced }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.space3)
    }
}

private struct TabButton: View {
    let icon: String
    let label: LocalizedStringKey
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.space1) {
                Image(systemName: icon).font(.ui(size: 19))
                Text(label).font(.ui(size: 11))
            }
            .frame(width: 78, height: 48)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                    .fill(selected ? Theme.accentSoft : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                    .strokeBorder(selected ? Theme.accent.opacity(0.55) : .clear, lineWidth: 1)
            )
            .foregroundStyle(selected ? Theme.accent : Theme.textPrimary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Advanced

private struct AdvancedTab: View {
    @ObservedObject var model: SettingsModel
    @State private var showCodexHelp = false

    var body: some View {
        Form {
            Section("Agent integrations") {
                ForEach(model.agents) { agent in
                    HStack(spacing: Theme.space3) {
                        VStack(alignment: .leading, spacing: Theme.space1) {
                            Text(agent.displayName)
                                .foregroundStyle(Theme.textPrimary)
                            if agent.kind == .codex, model.isInstalled(.codex) {
                                Text("Installed, needs a one-time trust (tap ?)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.warning)
                            } else if let note = agent.note {
                                Text(note).font(.caption).foregroundStyle(Theme.textMuted)
                            } else if model.isInstalled(agent.kind) {
                                Text("Hook installed").font(.caption).foregroundStyle(Theme.success)
                            }
                        }
                        Spacer()
                        if agent.kind == .codex {
                            Button { showCodexHelp = true } label: {
                                Image(systemName: "questionmark.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("How to connect Codex")
                            .foregroundStyle(Theme.textMuted)
                        }
                        if agent.isSupported {
                            Button(model.isInstalled(agent.kind) ? "Remove" : "Install") {
                                model.toggleInstall(agent.kind)
                            }
                            .buttonStyle(model.isInstalled(agent.kind) ? BorderedButtonStyle() : AccentButtonStyle())
                        } else {
                            Text("Coming soon").foregroundStyle(Theme.textMuted)
                        }
                    }
                }
                if let err = model.installError {
                    Text(err).font(.caption).foregroundStyle(Theme.danger).textSelection(.enabled)
                }
            } footer: {
                Text("Install a hook so DesktopPet can mirror your coding agents in the bubble.")
                    .foregroundStyle(Theme.textMuted)
            }

            Section("Bash approval gate") {
                HStack(spacing: Theme.space3) {
                    VStack(alignment: .leading, spacing: Theme.space1) {
                        Text("Approve Bash from the bubble")
                            .foregroundStyle(Theme.textPrimary)
                        Text("Claude Code Bash requests show Allow/Deny in the bubble instead of the terminal.")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    ColorSwitch(isOn: $model.approvalGateEnabled)
                }
            }

            HistoryTabView()
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showCodexHelp) { CodexHelpView() }
    }
}

private struct SoundRow: View {
    let title: LocalizedStringKey
    @Binding var enabled: Bool
    let customPath: String
    let onPlay: () -> Void
    let onUpload: () -> Void
    let onReset: () -> Void

    private var sourceLabel: String {
        customPath.isEmpty ? "Default" : (customPath as NSString).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            HStack(spacing: Theme.space3) {
                Text(title)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                ColorSwitch(isOn: $enabled)
            }
            HStack(spacing: Theme.space2) {
                Text(sourceLabel)
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                Spacer()
                Button { onPlay() } label: { Image(systemName: "play.circle") }
                    .buttonStyle(BorderedButtonStyle())
                Button("Upload…") { onUpload() }
                    .buttonStyle(BorderedButtonStyle())
                if !customPath.isEmpty {
                    Button("Default") { onReset() }
                        .buttonStyle(BorderedButtonStyle())
                }
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.5)
        }
    }
}

// MARK: - General (merged setup + general)

private struct GeneralTab: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var pet: PetController
    @ObservedObject private var sound = SoundSettings.shared
    @ObservedObject private var appLang = AppLanguage.shared
    @ObservedObject private var breaks = BreakReminderSettings.shared
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section("Language") {
                Picker("Language", selection: $appLang.lang) {
                    ForEach(AppLanguage.Lang.allCases) { l in
                        Text(l.label).tag(l)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Launch") {
                HStack(spacing: Theme.space3) {
                    VStack(alignment: .leading, spacing: Theme.space1) {
                        Text("Launch at login")
                            .foregroundStyle(Theme.textPrimary)
                        Text("DesktopPet starts automatically when you sign in.")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    ColorSwitch(isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            LoginItem.setEnabled(newValue)
                            launchAtLogin = LoginItem.isEnabled
                        }))
                }
            }

            Section("Pet display") {
                HStack(spacing: Theme.space3) {
                    VStack(alignment: .leading, spacing: Theme.space1) {
                        Text("Animate pets")
                            .foregroundStyle(Theme.textPrimary)
                        Text("Turn off to freeze pet/bubble animation (lower CPU).")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    ColorSwitch(isOn: $pet.animationsEnabled)
                }
                HStack(spacing: Theme.space3) {
                    VStack(alignment: .leading, spacing: Theme.space1) {
                        Text("Animation speed")
                            .foregroundStyle(Theme.textPrimary)
                        Text("Sprite frame rate. Idle is always capped at 2 fps.")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    HStack(spacing: Theme.space2) {
                        Slider(value: $pet.animationFPS, in: 1...12, step: 1)
                            .frame(width: 120)
                            .tint(Theme.accent)
                        Text("\(Int(pet.animationFPS)) fps")
                            .monospacedDigit()
                            .foregroundStyle(Theme.textMuted)
                            .fixedSize()
                    }
                }
                .disabled(!pet.animationsEnabled)
                .opacity(pet.animationsEnabled ? 1 : 0.5)
            }

            Section("Break reminder") {
                HStack(spacing: Theme.space3) {
                    VStack(alignment: .leading, spacing: Theme.space1) {
                        Text("Remind me to take breaks")
                            .foregroundStyle(Theme.textPrimary)
                        Text("The home pet nudges you to rest after a work stretch.")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    ColorSwitch(isOn: $breaks.enabled)
                }
                Stepper("Work for: \(breaks.workIntervalMinutes) min",
                        value: $breaks.workIntervalMinutes, in: 15...240, step: 15)
                    .disabled(!breaks.enabled)
                    .opacity(breaks.enabled ? 1 : 0.5)
                Stepper("Break length: \(breaks.breakLengthMinutes) min",
                        value: $breaks.breakLengthMinutes, in: 1...30, step: 1)
                    .disabled(!breaks.enabled)
                    .opacity(breaks.enabled ? 1 : 0.5)
            }

            Section("Notifications") {
                HStack(spacing: Theme.space3) {
                    VStack(alignment: .leading, spacing: Theme.space1) {
                        Text(notificationTitle)
                            .foregroundStyle(Theme.textPrimary)
                        Text(notificationDetail)
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    notificationButton
                }
            }

            Section("Sounds") {
                SoundRow(title: "When a task finishes",
                         enabled: $sound.doneEnabled,
                         customPath: sound.doneCustomPath,
                         onPlay: { sound.play(.done) },
                         onUpload: { sound.upload(for: .done) },
                         onReset: { sound.resetToDefault(.done) })
                SoundRow(title: "When your pet needs you",
                         enabled: $sound.waitingEnabled,
                         customPath: sound.waitingCustomPath,
                         onPlay: { sound.play(.waiting) },
                         onUpload: { sound.upload(for: .waiting) },
                         onReset: { sound.resetToDefault(.waiting) })
            }

            Section("About") {
                VStack(spacing: Theme.space3) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                            .fill(Theme.accentSoft)
                        Image(systemName: "pawprint.fill")
                            .font(.ui(size: 32, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .frame(width: 64, height: 64)
                    .shadow(color: Theme.accentGlow, radius: 12, y: 3)

                    Text("DesktopPet")
                        .font(.title2.bold())
                        .foregroundStyle(Theme.textPrimary)
                    Text("A desktop pet that keeps you company while you work.")
                        .font(.callout)
                        .foregroundStyle(Theme.textMuted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.space3)
                LabeledContent("Version", value: appVersion)
                    .foregroundStyle(Theme.textMuted)
            }

            Section {
                Button("Quit DesktopPet") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(BorderedButtonStyle())
            }
        }
        .formStyle(.grouped)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private var notificationTitle: String {
        switch model.notificationState {
        case .enabled: return model.notificationsEnabled ? NSLocalizedString("Notifications on", comment: "") : NSLocalizedString("Notifications muted", comment: "")
        case .denied: return NSLocalizedString("Notifications denied", comment: "")
        case .unavailable: return NSLocalizedString("Notifications unavailable", comment: "")
        case .notDetermined: return NSLocalizedString("Enable notifications", comment: "")
        }
    }

    private var notificationDetail: String {
        switch model.notificationState {
        case .unavailable: return NSLocalizedString("Available once installed as DesktopPet.app", comment: "")
        case .denied: return NSLocalizedString("Turn on in System Settings to get alerts", comment: "")
        case .enabled: return model.notificationsEnabled
            ? NSLocalizedString("Alerts when something needs your attention.", comment: "")
            : NSLocalizedString("Muted, the toggle turns alerts back on", comment: "")
        case .notDetermined: return NSLocalizedString("Alerts when something needs your attention.", comment: "")
        }
    }

    @ViewBuilder private var notificationButton: some View {
        switch model.notificationState {
        case .enabled:
            ColorSwitch(isOn: $model.notificationsEnabled)
        case .denied:
            Button("Open Settings") { model.openSystemNotificationSettings() }
                .buttonStyle(BorderedButtonStyle())
        case .notDetermined:
            Button("Enable") { model.enableNotifications() }
                .buttonStyle(AccentButtonStyle())
        case .unavailable:
            EmptyView()
        }
    }
}

// MARK: - Pet tab

private struct PetTab: View {
    @ObservedObject var pet: PetController
    @ObservedObject var imagePets: ImagePetStore
    @ObservedObject var model: SettingsModel
    let selectedPack: ImagePetPack?
    @ObservedObject private var projectSettings = ProjectPetSettings.shared
    @State private var browsing = false
    @State private var creating = false
    @State private var petQuery = ""
    @State private var renameText = ""

    private enum PetSlot: Hashable {
        case defaultPet
        case project(String)
    }
    @State private var selectedSlot: PetSlot = .defaultPet

    private var selectedSlotPetID: String? {
        switch selectedSlot {
        case .defaultPet: return pet.selectedPetID
        case .project(let path): return projectSettings.petID(forProject: path)
        }
    }

    private var selectedSlotPack: ImagePetPack? {
        selectedSlotPetID.flatMap { imagePets.pack(id: $0) }
    }

    private var filteredPacks: [ImagePetPack] {
        guard !petQuery.isEmpty else { return imagePets.packs }
        let q = petQuery.lowercased()
        return imagePets.packs.filter { $0.displayName.lowercased().contains(q) }
    }

    var body: some View {
        Form {
            Section {
                heroCard
            }

            Section {
                HStack(spacing: Theme.space3) {
                    VStack(alignment: .leading, spacing: Theme.space1) {
                        Text("Split pet")
                            .foregroundStyle(Theme.textPrimary)
                        Text("Spawn one pet per active project instead of one shared pet.")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    ColorSwitch(isOn: $pet.splitPet)
                }
                if pet.splitPet {
                    HStack(spacing: Theme.space3) {
                        VStack(alignment: .leading, spacing: Theme.space1) {
                            Text("Hide idle project pets")
                                .foregroundStyle(Theme.textPrimary)
                            Text("Show a configured project's pet only while it's working; hide it when idle.")
                                .font(.caption)
                                .foregroundStyle(Theme.textMuted)
                        }
                        Spacer()
                        ColorSwitch(isOn: $pet.hideIdleProjectPets)
                    }
                }
            }

            Section {
                slotGrid
            }

            configPanel
        }
        .formStyle(.grouped)
        .onChange(of: pet.splitPet) { _ in
            if !pet.splitPet, case .project = selectedSlot {
                selectedSlot = .defaultPet
            }
        }
        .onChange(of: projectSettings.mappings) { _ in
            if case .project(let path) = selectedSlot,
               !projectSettings.mappings.contains(where: { $0.projectPath == path }) {
                selectedSlot = .defaultPet
            }
        }
        .sheet(isPresented: $browsing) { BrowsePetsView(onClose: { browsing = false }) }
        .sheet(isPresented: $creating) {
            CreatePetView(onCreate: { id in creating = false; imagePets.reload(); pet.selectedPetID = id },
                          onCancel: { creating = false })
        }
    }

    // MARK: - Hero card

    @ViewBuilder private var heroCard: some View {
        HStack(spacing: Theme.space3) {
            slotPetPreview
                .frame(width: 84, height: 84)
                .themedCard(padding: 0, radius: Theme.radiusMd, fill: Theme.cardHover, stroke: Theme.cardStroke)
            VStack(alignment: .leading, spacing: Theme.space1) {
                switch selectedSlot {
                case .defaultPet:
                    HStack(spacing: Theme.space2) {
                        Text(imagePets.displayName(for: pet.selectedPetID))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if let pack = selectedPack {
                            levelBadge(for: pack.id)
                        }
                    }
                    if let desc = selectedPack?.description {
                        Text(desc)
                            .font(.callout)
                            .foregroundStyle(Theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .project(let path):
                    Text((path as NSString).lastPathComponent)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let pack = selectedSlotPack {
                        HStack(spacing: Theme.space2) {
                            Text(pack.displayName)
                                .font(.callout)
                                .foregroundStyle(Theme.textMuted)
                            levelBadge(for: pack.id)
                        }
                    }
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
        }
    }

    // MARK: - Slot grid

    private var slotGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                  alignment: .leading, spacing: 12) {
            slotButton(for: .defaultPet, petID: pet.selectedPetID,
                       label: NSLocalizedString("Default", comment: "default pet slot"))
            if pet.splitPet {
                ForEach(projectSettings.mappings, id: \.projectPath) { mapping in
                    slotButton(for: .project(mapping.projectPath), petID: mapping.petID,
                               label: (mapping.projectPath as NSString).lastPathComponent)
                }
                addProjectSlot
            }
        }
        .padding(.vertical, Theme.space1)
    }

    private func slotButton(for slot: PetSlot, petID: String?, label: String) -> some View {
        let isSelected = selectedSlot == slot
        return Button { selectedSlot = slot } label: {
            VStack(spacing: Theme.space1) {
                Group {
                    if let petID, let pack = imagePets.pack(id: petID), let frame = pack.clip(0).first {
                        Image(nsImage: frame).resizable().interpolation(.high).scaledToFit()
                    } else {
                        Image(systemName: "pawprint.fill")
                            .font(.ui(size: 20))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .frame(width: 48, height: 48)
                Text(label)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(width: 64)
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .fill(isSelected ? Theme.accentSoft : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent : Theme.cardStroke,
                                  lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            if let petID {
                let level = PetCare.displayLevel(forXP: PetCareController.shared.states[petID]?.xp ?? 0)
                Text(verbatim: "Lv \(level)")
                    .font(.ui(size: 9, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(Capsule().fill(level > 0 ? Theme.accent.opacity(0.85) : Theme.textMuted.opacity(0.45)))
                    .foregroundStyle(.white)
                    .offset(x: -3, y: -3)
            }
        }
        .overlay(alignment: .topTrailing) {
            if case .project(let path) = slot {
                Button {
                    if selectedSlot == slot { selectedSlot = .defaultPet }
                    projectSettings.remove(projectPath: path)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.ui(size: 15))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Theme.textDisabled)
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
                .help("Remove project")
            }
        }
    }

    private var addProjectSlot: some View {
        Button { addProject() } label: {
            VStack(spacing: Theme.space1) {
                Image(systemName: "plus")
                    .font(.ui(size: 20))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 48, height: 48)
                Text("Add…")
                    .font(.caption)
                    .lineLimit(1)
                    .frame(width: 64)
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(6)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .strokeBorder(Theme.cardStroke, style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Config panel (switches on selected slot)

    @ViewBuilder private var configPanel: some View {
        switch selectedSlot {
        case .defaultPet:
            defaultPetConfig
        case .project(let path):
            projectPetConfig(path: path)
        }
    }

    @ViewBuilder private var defaultPetConfig: some View {
        if let id = pet.selectedPetID {
            Section {
                HStack(spacing: Theme.space2) {
                    TextField("Pet name", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { imagePets.rename(id, to: renameText) }
                    Button("Save") { imagePets.rename(id, to: renameText) }
                        .buttonStyle(AccentButtonStyle())
                        .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Name")
            } footer: {
                Text("Give your companion a custom name. Clear it to use the original.")
                    .foregroundStyle(Theme.textMuted)
            }
            .onAppear { renameText = imagePets.displayName(for: id) }
            .onChange(of: pet.selectedPetID) { _ in
                renameText = imagePets.displayName(for: pet.selectedPetID)
            }
        }

        Section("Choose pet") {
            if imagePets.packs.isEmpty {
                Text("No pets yet. Tap Browse to add one.")
                    .foregroundStyle(Theme.textMuted)
            } else {
                if imagePets.packs.count > 4 {
                    NativeSearchField(text: $petQuery, placeholder: "Search your pets")
                }
                PetPager(packs: filteredPacks, selectedID: pet.selectedPetID,
                         onSelect: { pet.selectedPetID = $0 },
                         onDelete: { pack in
                             let wasSelected = pet.selectedPetID == pack.id
                             imagePets.delete(pack)
                             if wasSelected { pet.selectedPetID = imagePets.packs.first?.id }
                         })
            }
            HStack(spacing: Theme.space2) {
                Button { browsing = true } label: {
                    Label("Browse pets…", systemImage: "square.grid.2x2")
                }
                .buttonStyle(BorderedButtonStyle())
                Button { creating = true } label: {
                    Label("Create pet…", systemImage: "square.and.pencil")
                }
                .buttonStyle(BorderedButtonStyle())
            }
        }

        if let pack = selectedPack {
            Section("Animations") {
                AnimationPicker(pack: pack)
            }
        }

        Section("Size on screen") {
            HStack(spacing: Theme.space2) {
                Slider(value: $pet.petPoint, in: PetController.minPoint...PetController.maxPoint)
                    .tint(Theme.accent)
                Text("\(Int(pet.petPoint))")
                    .monospacedDigit()
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize()
                ForEach(PetController.presets, id: \.0) { preset in
                    Button(preset.0) { pet.animateSize(to: preset.1) }
                        .buttonStyle(BorderedButtonStyle())
                }
            }
        }
    }

    @ViewBuilder private func projectPetConfig(path: String) -> some View {
        Section("Choose pet") {
            if imagePets.packs.isEmpty {
                Text("No pets installed.")
                    .foregroundStyle(Theme.textMuted)
            } else {
                PetPager(packs: imagePets.packs,
                         selectedID: projectSettings.petID(forProject: path),
                         onSelect: { projectSettings.setPet(projectPath: path, petID: $0) })
            }
        }

        if let pack = selectedSlotPack {
            Section("Animations") {
                AnimationPicker(pack: pack)
            }
        }

        Section {
            Button(role: .destructive) {
                projectSettings.remove(projectPath: path)
            } label: {
                Label("Remove project", systemImage: "trash")
                    .foregroundStyle(Theme.danger)
            }
            .buttonStyle(BorderedButtonStyle())
        }
    }

    // MARK: - Helpers

    @ViewBuilder private var slotPetPreview: some View {
        if let pack = selectedSlotPack {
            ImageSpriteView(frames: pack.clip(0), mood: .idle,
                            fps: pet.spriteFPS(forMood: .idle), size: 78)
        } else {
            Image(systemName: "pawprint.fill")
                .font(.ui(size: 40))
                .foregroundStyle(Theme.textMuted)
        }
    }

    private func levelBadge(for packID: String) -> some View {
        Text(verbatim: "Lv \(PetCare.displayLevel(forXP: PetCareController.shared.states[packID]?.xp ?? 0))")
            .font(.caption.weight(.bold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(Theme.accentSoft))
            .foregroundStyle(Theme.accent)
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.title = "Choose Project Folder"
        panel.prompt = "Add"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let petID = pet.selectedPetID ?? imagePets.packs.first?.id ?? ""
        guard !petID.isEmpty else { return }
        projectSettings.setPet(projectPath: url.path, petID: petID)
    }
}

// MARK: - Components

/// A single static sprite frame (no TimelineView), for grids where animating
/// every cell would be janky. Only the hero preview animates.
private struct StaticFrame: View {
    let image: NSImage?
    var size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "pawprint.fill").foregroundStyle(Theme.textMuted)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct PetPager: View {
    let packs: [ImagePetPack]
    let selectedID: String?
    let onSelect: (String) -> Void
    var onDelete: ((ImagePetPack) -> Void)? = nil
    @State private var page = 0

    private let perPage = 8

    var body: some View {
        let pageCount = max(1, Int(ceil(Double(packs.count) / Double(perPage))))
        let current = min(page, pageCount - 1)

        VStack(spacing: Theme.space3) {
            GeometryReader { geo in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(0..<pageCount, id: \.self) { p in
                        grid(for: p).frame(width: geo.size.width, alignment: .top)
                    }
                }
                .offset(x: -CGFloat(current) * geo.size.width)
                .animation(Theme.easeMedium, value: current)
            }
            .frame(height: 188)
            .clipped()

            if pageCount > 1 {
                HStack(spacing: Theme.space3) {
                    arrow("chevron.left", enabled: current > 0) { page = max(0, current - 1) }
                    HStack(spacing: 5) {
                        ForEach(0..<pageCount, id: \.self) { i in
                            Circle()
                                .fill(i == current ? Theme.accent : Theme.textMuted.opacity(0.4))
                                .frame(width: 6, height: 6)
                        }
                    }
                    arrow("chevron.right", enabled: current < pageCount - 1) { page = min(pageCount - 1, current + 1) }
                }
            }
        }
        .padding(.vertical, Theme.space1)
        .onChange(of: packs.count) { _ in page = 0 }
    }

    private func grid(for pageIndex: Int) -> some View {
        let slice = Array(packs.dropFirst(pageIndex * perPage).prefix(perPage))
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                         alignment: .leading, spacing: 12) {
            ForEach(slice) { pack in
                PetThumb(pack: pack, selected: selectedID == pack.id,
                         select: { onSelect(pack.id) },
                         onDelete: onDelete.map { d in { d(pack) } })
            }
        }
    }

    private func arrow(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Theme.textSecondary : Theme.textDisabled)
        .disabled(!enabled)
    }
}

private struct PetThumb: View {
    let pack: ImagePetPack
    let selected: Bool
    let select: () -> Void
    var onDelete: (() -> Void)? = nil
    @State private var hovering = false

    private var level: Int {
        PetCare.displayLevel(forXP: PetCareController.shared.states[pack.id]?.xp ?? 0)
    }

    var body: some View {
        Button(action: select) {
            VStack(spacing: Theme.space1) {
                StaticFrame(image: pack.clip(0).first, size: 48)
                    .frame(width: 56, height: 48)
                Text(pack.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(width: 64)
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .fill(selected ? Theme.accentSoft : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Theme.cardStroke, lineWidth: selected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            Text(verbatim: "Lv \(level)")
                .font(.ui(size: 9, weight: .bold))
                .padding(.horizontal, 5).padding(.vertical, 1.5)
                .background(Capsule().fill(level > 0 ? Theme.accent.opacity(0.85) : Theme.textMuted.opacity(0.45)))
                .foregroundStyle(.white)
                .offset(x: -3, y: -3)
        }
        .overlay(alignment: .topTrailing) {
            if hovering, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.ui(size: 15))
                        .foregroundStyle(.white, Theme.textDisabled)
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .onHover { hovering = $0 }
    }
}

private struct AnimationPicker: View {
    let pack: ImagePetPack
    @ObservedObject private var store = PetBindingsStore.shared
    @ObservedObject private var pet = PetController.shared
    @State private var state: PetMood = .working
    @State private var hoveredClip: Int?

    private let states: [PetMood] = [.idle, .working, .waiting, .done, .celebrate, .sleepy, .levelup]

    var body: some View {
        Picker("State", selection: $state) {
            ForEach(states, id: \.self) { Text(label($0)).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        Text("Hover a clip to preview it.")
            .font(.caption2)
            .foregroundStyle(Theme.textMuted)

        let current = store.clipIndex(packId: pack.id, clipCount: pack.clipCount, mood: state)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], spacing: 10) {
            ForEach(0..<pack.clipCount, id: \.self) { i in
                Button {
                    store.setClip(i, mood: state, packId: pack.id, clipCount: pack.clipCount)
                } label: {
                    VStack(spacing: Theme.space1) {
                        Group {
                            if hoveredClip == i {
                                ImageSpriteView(frames: pack.clip(i), mood: .working,
                                                fps: pet.spriteFPS(forMood: .working), size: 44)
                            } else {
                                StaticFrame(image: pack.clip(i).first, size: 44)
                            }
                        }
                        .frame(width: 54, height: 44)
                        Text("Clip \(i + 1)")
                            .font(.caption2)
                            .foregroundStyle(Theme.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Theme.space1)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                            .fill(i == current ? Theme.accentSoft : .clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                            .strokeBorder(i == current ? Theme.accent : Theme.cardStroke, lineWidth: i == current ? 2 : 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hoveredClip = $0 ? i : (hoveredClip == i ? nil : hoveredClip) }
            }
        }
        .padding(.vertical, Theme.space1)
    }

    private func label(_ mood: PetMood) -> String {
        switch mood {
        case .idle: return NSLocalizedString("Idle", comment: "pet mood")
        case .working: return NSLocalizedString("Working", comment: "pet mood")
        case .waiting: return NSLocalizedString("Waiting", comment: "pet mood")
        case .done: return NSLocalizedString("Done", comment: "pet mood")
        case .celebrate: return NSLocalizedString("Celebrate", comment: "pet mood")
        case .sleepy: return NSLocalizedString("Sleepy", comment: "pet mood")
        case .levelup: return NSLocalizedString("Level up", comment: "pet mood")
        }
    }
}

// MARK: - Codex connection help

/// Explains the one-time `/hooks` trust step Codex requires before DesktopPet's
/// hook runs (Codex blocks unknown command hooks for security). Other agents
/// need no such step.
private struct CodexHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Step: Identifiable { let n: Int; let text: String; var id: Int { n } }
    private let steps: [Step] = [
        .init(n: 1, text: NSLocalizedString("Open Terminal and run: codex (launches the Codex CLI)", comment: "codex help step")),
        .init(n: 2, text: NSLocalizedString("Type /hooks and press Enter to list the hooks.", comment: "codex help step")),
        .init(n: 3, text: NSLocalizedString("Press t to Trust all hooks.", comment: "codex help step")),
        .init(n: 4, text: NSLocalizedString("Quit and reopen Codex (both the CLI and the desktop app).", comment: "codex help step")),
        .init(n: 5, text: NSLocalizedString("Run any prompt, your pet now shows the Codex session.", comment: "codex help step")),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space4) {
            HStack(spacing: Theme.space3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                        .fill(Theme.infoSoft)
                    Image(systemName: "checkmark.shield")
                        .font(.ui(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.info)
                }
                .frame(width: 34, height: 34)
                Text("Connect Codex")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }

            Text("The hook is installed. Codex blocks unknown command hooks until you trust them once, a Codex security feature, not an DesktopPet bug. Do this one time:")
                .font(.callout)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Theme.space3) {
                ForEach(steps) { s in
                    HStack(alignment: .top, spacing: Theme.space3) {
                        Text("\(s.n)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Theme.info))
                        Text(s.text)
                            .font(.callout)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }

            Text("Trust is shared, so trusting once in the CLI also covers the Codex desktop app. If /hooks shows nothing, add [features] hooks = true to ~/.codex/config.toml, then retry.")
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Link("Codex hooks docs", destination: URL(string: "https://developers.openai.com/codex/hooks")!)
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                Spacer()
                Button("Got it") { dismiss() }
                    .buttonStyle(AccentButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.space5)
        .frame(width: 460)
        .background(Theme.background)
        .themedCard(shadow: true)
        .preferredColorScheme(.dark)
    }
}
