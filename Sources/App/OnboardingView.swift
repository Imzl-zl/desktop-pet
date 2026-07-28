import SwiftUI
import DesktopPetCore

/// First-launch welcome: pick a pet first, then optionally enable notifications
/// or connect coding agents from the Advanced tab later.
struct OnboardingView: View {
    @ObservedObject private var model = SettingsModel.shared
    @ObservedObject private var pet = PetController.shared
    @ObservedObject private var imagePets = ImagePetStore.shared
    var onFinish: () -> Void

    @State private var browsing = false
    @State private var creating = false

    private var selectedPack: ImagePetPack? {
        pet.selectedPetID.flatMap { imagePets.pack(id: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space5) {
                header
                petStep
                notificationStep
                agentStep
                HStack {
                    Spacer()
                    Button("Get started") { onFinish() }
                        .buttonStyle(AccentButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(EdgeInsets(top: Theme.space8, leading: Theme.space6, bottom: Theme.space6, trailing: Theme.space6))
        }
        .frame(width: 640, height: 640)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .noFocusRing()
        .onAppear { model.refresh() }
        .sheet(isPresented: $browsing) { BrowsePetsView(onClose: { browsing = false }) }
        .sheet(isPresented: $creating) {
            CreatePetView(
                onCreate: { id in
                    creating = false
                    imagePets.reload()
                    pet.selectedPetID = id
                },
                onCancel: { creating = false }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            HStack(spacing: Theme.space3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                        .fill(Theme.accent)
                    Image(systemName: "pawprint.fill")
                        .font(.ui(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
                .shadow(color: Theme.accentGlow, radius: 10, y: 2)

                Text("Welcome to DesktopPet")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("A desktop companion that keeps you company while you work. Pick a pet to get started.")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // Step 1: pet
    private var petStep: some View {
        VStack(alignment: .leading, spacing: Theme.space3) {
            stepLabel(1, "Pick your pet")
            HStack(spacing: Theme.space4) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous)
                        .fill(Theme.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous)
                                .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1)
                        )
                    if let pack = selectedPack {
                        ImageSpriteView(frames: pack.clip(0), mood: .idle,
                                        fps: pet.spriteFPS(forMood: .idle), size: 90)
                    } else {
                        Image(systemName: "pawprint.fill")
                            .font(.ui(size: 40, weight: .semibold))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: Theme.space2) {
                    Text(selectedPack?.displayName ?? "Loading a starter pet…")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    if let d = selectedPack?.description {
                        Text(d)
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                            .lineLimit(3)
                    }
                    HStack(spacing: Theme.space2) {
                        Button { browsing = true } label: {
                            Label("Browse pets", systemImage: "square.grid.2x2")
                        }
                        .buttonStyle(BorderedButtonStyle())
                        Button { creating = true } label: {
                            Label("Create pet", systemImage: "square.and.pencil")
                        }
                        .buttonStyle(BorderedButtonStyle())
                    }
                }
                Spacer()
            }
        }
        .themedCard()
    }

    // Step 2: notifications (optional)
    private var notificationStep: some View {
        HStack(spacing: Theme.space3) {
            VStack(alignment: .leading, spacing: Theme.space1) {
                Text("Enable notifications")
                    .foregroundStyle(Theme.textPrimary)
                Text("Get alerted when something needs your attention.")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            switch model.notificationState {
            case .enabled:
                Label("On", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
                    .font(.caption)
            case .denied:
                Button("Open Settings") { model.openSystemNotificationSettings() }
                    .buttonStyle(BorderedButtonStyle())
            case .notDetermined:
                Button("Enable") { model.enableNotifications() }
                    .buttonStyle(AccentButtonStyle())
            case .unavailable:
                Text("—")
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .themedCard()
    }

    // Step 3: coding agents (optional, advanced)
    private var agentStep: some View {
        VStack(alignment: .leading, spacing: Theme.space3) {
            HStack(spacing: Theme.space2) {
                stepLabel(3, "Connect coding agents")
                Text("(optional)")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }
            Text("Install a hook so DesktopPet can mirror your coding agents in the bubble. You can always do this later in Advanced settings.")
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
            ForEach(model.agents) { agent in
                HStack(spacing: Theme.space3) {
                    Text(agent.displayName)
                        .foregroundStyle(Theme.textPrimary)
                    if model.isInstalled(agent.kind) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.success)
                            .font(.caption)
                    }
                    Spacer()
                    Button(model.isInstalled(agent.kind) ? "Connected" : "Connect") {
                        model.toggleInstall(agent.kind)
                    }
                    .buttonStyle(model.isInstalled(agent.kind) ? BorderedButtonStyle() : AccentButtonStyle())
                    .disabled(model.isInstalled(agent.kind))
                }
            }
        }
        .themedCard()
    }

    private func stepLabel(_ n: Int, _ title: String) -> some View {
        HStack(spacing: Theme.space2) {
            Text("\(n)")
                .font(.ui(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.accent))
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
        }
    }
}
