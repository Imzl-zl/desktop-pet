import SwiftUI
import AgentPetCore

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
            VStack(alignment: .leading, spacing: 22) {
                header
                petStep
                notificationStep
                agentStep
                HStack {
                    Spacer()
                    Button("Get started") { onFinish() }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.systemAccent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(EdgeInsets(top: 40, leading: 28, bottom: 28, trailing: 28))
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.systemAccent).frame(width: 34, height: 34)
                    .overlay(Image(systemName: "pawprint.fill").font(.system(size: 17)).foregroundStyle(.white))
                Text("Welcome to AgentPet").font(.title2.bold()).foregroundStyle(.white)
            }
            Text("A desktop companion that keeps you company while you work. Pick a pet to get started.")
                .font(.callout).foregroundStyle(.white.opacity(0.7))
        }
    }

    // Step 1: pet
    private var petStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepLabel(1, "Pick your pet")
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.systemAccent.opacity(0.3)))
                    if let pack = selectedPack {
                        ImageSpriteView(frames: pack.clip(0), mood: .idle,
                                        fps: pet.spriteFPS(forMood: .idle), size: 90)
                    } else {
                        Image(systemName: "pawprint.fill").font(.system(size: 40)).foregroundStyle(.white.opacity(0.3))
                    }
                }
                .frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedPack?.displayName ?? "Loading a starter pet…")
                        .font(.headline).foregroundStyle(.white)
                    if let d = selectedPack?.description {
                        Text(d).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(3)
                    }
                    HStack {
                        Button { browsing = true } label: {
                            Label("Browse pets", systemImage: "square.grid.2x2")
                        }
                        Button { creating = true } label: {
                            Label("Create pet", systemImage: "square.and.pencil")
                        }
                    }
                    .buttonStyle(.plain).foregroundStyle(Color.systemAccent)
                }
                Spacer()
            }
        }
        .themedCard()
    }

    // Step 2: notifications (optional)
    private var notificationStep: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Enable notifications").foregroundStyle(.white)
                Text("Get alerted when something needs your attention.")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            switch model.notificationState {
            case .enabled: Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
            case .denied: Button("Open Settings") { model.openSystemNotificationSettings() }
            case .notDetermined: Button("Enable") { model.enableNotifications() }
            case .unavailable: Text("—").foregroundStyle(.white.opacity(0.4))
            }
        }
        .themedCard()
    }

    // Step 3: coding agents (optional, advanced)
    private var agentStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                stepLabel(3, "Connect coding agents")
                Text("(optional)")
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            Text("Install a hook so AgentPet can mirror your coding agents in the bubble. You can always do this later in Advanced settings.")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
            ForEach(model.agents) { agent in
                HStack {
                    Text(agent.displayName).foregroundStyle(.white)
                    if model.isInstalled(agent.kind) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                    }
                    Spacer()
                    Button(model.isInstalled(agent.kind) ? "Connected" : "Connect") {
                        model.toggleInstall(agent.kind)
                    }
                    .disabled(model.isInstalled(agent.kind))
                }
            }
        }
        .themedCard()
    }

    private func stepLabel(_ n: Int, _ title: String) -> some View {
        HStack(spacing: 8) {
            Text("\(n)")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.systemAccent))
            Text(title).font(.headline).foregroundStyle(.white)
        }
    }
}
