import SwiftUI
import AppKit
import DesktopPetCore

/// Renders an imported spritesheet pet. The frame cycling runs in a CALayer
/// (see `SpriteLayerNSView`), NOT a SwiftUI `TimelineView`: a SwiftUI timeline
/// re-evaluates and re-renders the whole view tree every tick, and an
/// always-on-screen pet (×every window) made that the dominant CPU cost.
/// Swapping `layer.contents` on a timer animates in Core Animation instead, so
/// SwiftUI does not redraw the sprite per frame. The only SwiftUI animation
/// left here is the transient celebrate sparkle overlay (≈3s, mood `.celebrate`).
struct ImageSpriteView: View {
    /// Frames of the clip bound to the current mood (resolved by the caller).
    let frames: [NSImage]
    let mood: PetMood
    /// Sprite frame rate supplied by the caller (from `PetController.spriteFPS(forMood:)`).
    let fps: Double
    var size: CGFloat = 110
    @Environment(\.animationsEnabled) private var animationsEnabled

    var body: some View {
        ZStack {
            // Sparkles only exist for `.celebrate`, and celebrate is a short
            // transient — gate the (animated) overlay on it so idle/working
            // states carry no perpetual SwiftUI animation at all.
            // When animations are disabled, skip the celebrate overlay entirely.
            if mood == .celebrate && animationsEnabled {
                TimelineView(.periodic(from: .now, by: 1.0 / 8.0)) { context in
                    MoodAccessories(mood: mood,
                                    t: context.date.timeIntervalSinceReferenceDate,
                                    size: size)
                }
            }

            if frames.isEmpty {
                Image(systemName: "pawprint.fill").font(.system(size: 36))
            } else {
                SpriteLayer(frames: frames, fps: fps, size: size, animate: animationsEnabled)
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
    }
}

/// SwiftUI bridge to the CALayer-backed sprite player.
private struct SpriteLayer: NSViewRepresentable {
    let frames: [NSImage]
    let fps: Double
    let size: CGFloat
    var animate: Bool = true

    func makeNSView(context: Context) -> SpriteLayerNSView {
        let view = SpriteLayerNSView()
        view.configure(frames: frames, fps: fps, animate: animate)
        return view
    }

    func updateNSView(_ view: SpriteLayerNSView, context: Context) {
        // Called on every SwiftUI re-render of the parent (which, while a chat
        // bubble's perpetual animations run, can be ~display-rate). `configure`
        // is idempotent: it only rebuilds frames / restarts the timer when the
        // frames or fps actually change, so this never churns the timer.
        view.configure(frames: frames, fps: fps, animate: animate)
    }

    static func dismantleNSView(_ view: SpriteLayerNSView, coordinator: ()) {
        view.teardown()
    }
}

/// A layer-backed view that cycles CGImages by swapping `layer.contents` on a
/// timer at `fps`. No SwiftUI involvement per frame.
final class SpriteLayerNSView: NSView {
    private var cgFrames: [CGImage] = []
    private var sourceFrames: [NSImage] = []
    private var fps: Double = 3
    private var animate: Bool = true
    private var index = 0
    private var timer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.magnificationFilter = .linear
        layer?.minificationFilter = .linear
        layer?.contentsScale = window?.backingScaleFactor ?? 2
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func configure(frames: [NSImage], fps: Double, animate: Bool = true) {
        let framesChanged = frames.count != sourceFrames.count
            || !zip(frames, sourceFrames).allSatisfy { $0 === $1 }
        if framesChanged {
            sourceFrames = frames
            cgFrames = frames.compactMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
            index = 0
        }
        let fpsChanged = fps != self.fps
        self.fps = fps
        let animateChanged = animate != self.animate
        self.animate = animate
        if framesChanged || fpsChanged || animateChanged {
            restartTimer()
        }
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        // When animations are disabled, show frame 0 and start no timer.
        guard animate && cgFrames.count > 1 && fps > 0 else {
            showCurrent()
            return
        }
        showCurrent()
        // The Timer block is @Sendable, so it captures nothing; hop to the main
        // actor (where this NSView lives) to advance the frame.
        let t = Timer(timeInterval: 1.0 / fps, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.advance() }
        }
        // .common so the pet keeps animating during menu/scroll tracking.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func advance() {
        guard !cgFrames.isEmpty else { return }
        index = (index + 1) % cgFrames.count
        showCurrent()
    }

    private func showCurrent() {
        guard !cgFrames.isEmpty else { layer?.contents = nil; return }
        layer?.contents = cgFrames[index % cgFrames.count]
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.contentsScale = window?.backingScaleFactor ?? 2
    }

    /// Stops the frame timer. Called from `SpriteLayer.dismantleNSView` when the
    /// SwiftUI view is removed (Swift 6 forbids touching the non-Sendable timer
    /// from a nonisolated `deinit`).
    func teardown() {
        timer?.invalidate()
        timer = nil
    }
}
