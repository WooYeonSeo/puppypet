import SwiftUI

struct SpeechBubbleView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            )
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 180)
    }
}

/// Popover that shows the assistant's last-turn text body when the user taps
/// the bubble. Read-only, scrollable, selectable for copy.
struct SummaryPopover: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "본문이 비어있어요" : text)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(width: 320, height: min(420, max(80, estimatedHeight)))
    }

    private var estimatedHeight: CGFloat {
        // Rough heuristic so short bodies don't get a giant empty popover.
        let lineCount = max(1, text.components(separatedBy: "\n").count)
        let charCount = text.count
        let approx = CGFloat(lineCount) * 18 + CGFloat(charCount) / 30 * 18 + 24
        return min(420, max(80, approx))
    }
}
