import XCTest
import CoreGraphics
@testable import desktoppet

// MARK: - Helpers

/// Synthesises a 2-row x 3-column spritesheet.
///
/// Layout (image coordinates, y=0 at top):
///   - Outer padding: 6 px on every side
///   - Cell size: 20 x 24 px
///   - Gutter between cells: 8 px (fully transparent)
///
/// Total sheet: 6 + 20 + 8 + 20 + 8 + 20 + 6 = 88 px wide
///              6 + 24 + 8 + 24 + 6 = 68 px tall
///
/// Row 0 (top in image coords):   cells filled with red / green / blue
/// Row 1 (bottom in image coords): cells filled with cyan / magenta / yellow
///
/// CGContext y=0 is at the BOTTOM, so drawing order is inverted vertically.
private func makeSynthesisSheet() -> CGImage {
    let cellW = 20, cellH = 24
    let pad = 6, gutter = 8
    let cols = 3, rows = 2

    let sheetW = pad + cols * cellW + (cols - 1) * gutter + pad
    let sheetH = pad + rows * cellH + (rows - 1) * gutter + pad

    // bitmapInfo: premultipliedLast => RGBA
    let ctx = CGContext(
        data: nil,
        width: sheetW,
        height: sheetH,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // Row 0 colours (top of image -> higher CGContext y)
    let row0Colors: [CGColor] = [
        CGColor(red: 1, green: 0, blue: 0, alpha: 1), // red
        CGColor(red: 0, green: 1, blue: 0, alpha: 1), // green
        CGColor(red: 0, green: 0, blue: 1, alpha: 1), // blue
    ]
    // Row 1 colours (bottom of image -> lower CGContext y)
    let row1Colors: [CGColor] = [
        CGColor(red: 0, green: 1, blue: 1, alpha: 1), // cyan
        CGColor(red: 1, green: 0, blue: 1, alpha: 1), // magenta
        CGColor(red: 1, green: 1, blue: 0, alpha: 1), // yellow
    ]

    // In CGContext: y=0 is image-bottom.
    // Image-top row (row 0)  starts at image-y = pad
    //   -> CGContext y = sheetH - pad - cellH
    // Image-bottom row (row 1) starts at image-y = pad + cellH + gutter
    //   -> CGContext y = sheetH - (pad + cellH + gutter) - cellH

    let cgRow0Y = sheetH - pad - cellH
    let cgRow1Y = sheetH - pad - 2 * cellH - gutter

    for col in 0..<cols {
        let x = pad + col * (cellW + gutter)

        ctx.setFillColor(row0Colors[col])
        ctx.fill(CGRect(x: x, y: cgRow0Y, width: cellW, height: cellH))

        ctx.setFillColor(row1Colors[col])
        ctx.fill(CGRect(x: x, y: cgRow1Y, width: cellW, height: cellH))
    }

    return ctx.makeImage()!
}

// MARK: - Tests

final class SpriteSlicerTests: XCTestCase {

    // MARK: 1. Grid detection

    func test_slice_detects_grid_rows_and_columns() {
        let sheet = makeSynthesisSheet()
        let clips = SpriteSlicer.slice(sheet)

        XCTAssertEqual(clips.count, 2, "Should detect 2 row bands")
        for (i, clip) in clips.enumerated() {
            XCTAssertEqual(clip.count, 3, "Row \(i) should contain 3 frames")
            for (j, frame) in clip.enumerated() {
                XCTAssertEqual(frame.width, 20,  "Row \(i) col \(j) width should be 20 px")
                XCTAssertEqual(frame.height, 24, "Row \(i) col \(j) height should be 24 px")
            }
        }
    }

    // MARK: 2. Pixel content preservation

    func test_slice_frames_preserve_pixel_content() {
        let sheet = makeSynthesisSheet()
        let clips = SpriteSlicer.slice(sheet)

        // Collect all 6 frames (order may vary) and verify each has a non-transparent centre.
        let allFrames = clips.flatMap { $0 }
        XCTAssertEqual(allFrames.count, 6, "Expected 6 frames total")

        for (i, frame) in allFrames.enumerated() {
            let rgba = centerPixelRGBA(of: frame)
            XCTAssertGreaterThan(rgba.a, 200,
                "Frame \(i) centre pixel should be opaque, got alpha=\(rgba.a)")
        }

        // Verify diverse hues are present across frames.
        let dominantChannels = Set(allFrames.map { dominantChannel(of: $0) })
        XCTAssertGreaterThanOrEqual(dominantChannels.count, 3,
            "Expected diverse pixel colours across 6 frames, got \(dominantChannels)")
    }

    // MARK: 3. Backing-store ownership (RED -- MUST FAIL with current code)

    func test_slice_frames_own_their_backing_store() {
        let sheet = makeSynthesisSheet()
        let clips = SpriteSlicer.slice(sheet)

        for (rowIdx, clip) in clips.enumerated() {
            for (colIdx, frame) in clip.enumerated() {
                let expectedBytesPerRow = frame.width * 4
                XCTAssertEqual(
                    frame.bytesPerRow,
                    expectedBytesPerRow,
                    "Row \(rowIdx) col \(colIdx): bytesPerRow should be \(expectedBytesPerRow) " +
                    "(frame owns its backing store), but got \(frame.bytesPerRow) " +
                    "(parent sheet stride -- indicates cropping(to:) view is still alive)"
                )
            }
        }
    }

    // MARK: 4. Fully transparent image -> empty result

    func test_slice_returns_empty_for_fully_transparent_image() {
        let ctx = CGContext(
            data: nil,
            width: 60,
            height: 40,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Draw nothing -- all pixels remain transparent (alpha = 0).
        let blankSheet = ctx.makeImage()!

        let clips = SpriteSlicer.slice(blankSheet)
        XCTAssertTrue(clips.isEmpty, "Fully transparent sheet should produce no clips")
    }
}

// MARK: - Pixel helpers

private func centerPixelRGBA(of image: CGImage) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
    let w = 1, h = 1
    var data = [UInt8](repeating: 0, count: 4)
    let ctx = data.withUnsafeMutableBytes { ptr -> CGContext? in
        CGContext(
            data: ptr.baseAddress,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }!
    // Draw the frame scaled down to 1x1 to sample the centre colour.
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (data[0], data[1], data[2], data[3])
}

/// Returns a string key representing which channel(s) dominate the centre pixel.
private func dominantChannel(of image: CGImage) -> String {
    let px = centerPixelRGBA(of: image)
    let threshold: UInt8 = 128
    var parts: [String] = []
    if px.r > threshold { parts.append("R") }
    if px.g > threshold { parts.append("G") }
    if px.b > threshold { parts.append("B") }
    return parts.isEmpty ? "none" : parts.joined()
}
