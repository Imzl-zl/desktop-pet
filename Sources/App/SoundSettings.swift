import AppKit
import DesktopPetCore

/// Plays a sound when an agent finishes or needs input. Each event has its own
/// on/off and sound choice (a built-in macOS system sound, or a custom file the
/// user uploads). Custom files are copied into `~/.desktoppet/sounds/`.
@MainActor
final class SoundSettings: ObservableObject {
    static let shared = SoundSettings()

    enum Event: String { case waiting, done }

    @Published var waitingEnabled: Bool { didSet { save() } }
    @Published var doneEnabled: Bool { didSet { save() } }
    /// "" means use the built-in default; otherwise a custom file path.
    @Published var waitingCustomPath: String { didSet { save() } }
    @Published var doneCustomPath: String { didSet { save() } }

    /// Built-in macOS system sounds used as defaults.
    static let defaultWaiting = "Submarine"
    static let defaultDone = "Glass"

    private var soundsDir: URL {
        URL(fileURLWithPath: DesktopPetPaths.baseDir).appendingPathComponent("sounds")
    }

    init() {
        let d = UserDefaults.standard
        waitingEnabled = (d.object(forKey: "desktoppet.sound.waiting.on") as? Bool) ?? true
        doneEnabled = (d.object(forKey: "desktoppet.sound.done.on") as? Bool) ?? true
        waitingCustomPath = d.string(forKey: "desktoppet.sound.waiting.path") ?? ""
        doneCustomPath = d.string(forKey: "desktoppet.sound.done.path") ?? ""
    }

    func isEnabled(_ event: Event) -> Bool {
        event == .waiting ? waitingEnabled : doneEnabled
    }

    func customPath(_ event: Event) -> String {
        event == .waiting ? waitingCustomPath : doneCustomPath
    }

    /// Plays the configured sound for an event, if enabled.
    func play(_ event: Event) {
        guard isEnabled(event) else { return }
        let sound: NSSound?
        let path = customPath(event)
        if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
            sound = NSSound(contentsOfFile: path, byReference: true)
        } else {
            sound = NSSound(named: event == .waiting ? Self.defaultWaiting : Self.defaultDone)
        }
        sound?.stop()
        sound?.play()
    }

    /// Prompts for an audio file and sets it as the custom sound for an event.
    func upload(for event: Event) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a sound file"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let fm = FileManager.default
        try? fm.createDirectory(at: soundsDir, withIntermediateDirectories: true)
        let dest = soundsDir.appendingPathComponent("\(event.rawValue).\(url.pathExtension)")
        try? fm.removeItem(at: dest)
        do {
            try fm.copyItem(at: url, to: dest)
        } catch {
            return
        }
        setCustomPath(dest.path, for: event)
        play(event)   // preview
    }

    func resetToDefault(_ event: Event) {
        setCustomPath("", for: event)
    }

    private func setCustomPath(_ path: String, for event: Event) {
        if event == .waiting { waitingCustomPath = path } else { doneCustomPath = path }
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(waitingEnabled, forKey: "desktoppet.sound.waiting.on")
        d.set(doneEnabled, forKey: "desktoppet.sound.done.on")
        d.set(waitingCustomPath, forKey: "desktoppet.sound.waiting.path")
        d.set(doneCustomPath, forKey: "desktoppet.sound.done.path")
    }
}
