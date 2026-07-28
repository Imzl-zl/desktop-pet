import AppKit
import SwiftUI
import DesktopPetCore

/// Edits the project→pet mappings stored in `ProjectPetSettings`.
/// Listed in `PetTab` under the "Project pets" sub-tab.
struct ProjectPetsView: View {
    @ObservedObject var settings = ProjectPetSettings.shared
    @ObservedObject var imagePets = ImagePetStore.shared

    var body: some View {
        Form {
            if settings.mappings.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("No project pets yet.")
                            .font(.headline)
                        Text("Add a project folder to give it its own pet.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
            } else {
                Section("Configured projects") {
                    ForEach(settings.mappings, id: \.projectPath) { mapping in
                        MappingRow(mapping: mapping, imagePets: imagePets, settings: settings)
                    }
                }
            }

            Section {
                Button {
                    addProject()
                } label: {
                    Label("Add project…", systemImage: "folder.badge.plus")
                }
            }
        }
        .formStyle(.grouped)
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

        let petID = PetController.shared.selectedPetID
            ?? imagePets.packs.first?.id
            ?? ""
        guard !petID.isEmpty else { return }

        settings.setPet(projectPath: url.path, petID: petID)
    }
}

// MARK: - Single mapping row

private struct MappingRow: View {
    let mapping: ProjectPetMapping
    @ObservedObject var imagePets: ImagePetStore
    @ObservedObject var settings: ProjectPetSettings

    private var folderName: String {
        (mapping.projectPath as NSString).lastPathComponent
    }

    private var pack: ImagePetPack? {
        imagePets.pack(id: mapping.petID)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            thumbnail
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))

            // Path info
            VStack(alignment: .leading, spacing: 2) {
                Text(folderName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(mapping.projectPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Pet picker
            petPicker

            // Delete button
            Button {
                settings.remove(projectPath: mapping.projectPath)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.borderless)
            .help("Remove this project mapping")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let pack {
            if let frame = pack.clip(0).first {
                Image(nsImage: frame)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 36, height: 36)
            } else {
                Image(systemName: "pawprint.fill")
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                Text("missing")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var petPicker: some View {
        if imagePets.packs.isEmpty {
            Text("No pets installed")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Menu {
                ForEach(imagePets.packs) { p in
                    Button {
                        settings.setPet(projectPath: mapping.projectPath, petID: p.id)
                    } label: {
                        HStack {
                            Text(p.displayName)
                            if p.id == mapping.petID {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(pack?.displayName ?? "Missing pet")
                        .font(.callout)
                        .foregroundStyle(pack == nil ? .orange : .primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}
