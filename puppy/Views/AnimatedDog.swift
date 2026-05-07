import SwiftUI
import AppKit

enum SpriteSheet {
    /// CGImage 기준 top-left 좌표계로 sprite sheet을 columns x rows 프레임으로 분할.
    /// reading order (left→right, top→bottom)으로 반환.
    static func loadFrames(name: String, columns: Int, rows: Int) -> [NSImage] {
        guard let source = NSImage(named: name),
              let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }
        let frameW = cg.width / columns
        let frameH = cg.height / rows
        var frames: [NSImage] = []
        for row in 0..<rows {
            for col in 0..<columns {
                let rect = CGRect(x: col * frameW, y: row * frameH, width: frameW, height: frameH)
                if let cropped = cg.cropping(to: rect) {
                    let img = NSImage(cgImage: cropped, size: NSSize(width: frameW, height: frameH))
                    frames.append(img)
                }
            }
        }
        return frames
    }
}

struct WalkingDogView: View {
    let frames: [NSImage]
    var fps: Double = 8

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / fps)) { context in
            let idx = Int(context.date.timeIntervalSinceReferenceDate * fps) % max(frames.count, 1)
            if frames.indices.contains(idx) {
                Image(nsImage: frames[idx])
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
            }
        }
    }
}
