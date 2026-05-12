import SwiftUI
import AppKit

struct SpeechBubbleView: View {
    let text: String

    /// 여러 줄(bullet 리스트 등)이면 왼쪽 정렬, 단문이면 가운데 정렬.
    private var isMultiline: Bool { text.contains("\n") }

    var body: some View {
        BubbleText(text: text, alignment: isMultiline ? .left : .center, maxWidth: 180)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            )
            .frame(maxWidth: 180, alignment: isMultiline ? .leading : .center)
    }
}

/// SwiftUI Text는 byCharWrapping을 지원하지 않아 한국어/긴 문자열이 어색하게
/// 줄바꿈됨. NSTextField 래퍼로 어절 우선 + 필요 시 char 단위 break.
private struct BubbleText: NSViewRepresentable {
    let text: String
    let alignment: NSTextAlignment
    let maxWidth: CGFloat

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField(wrappingLabelWithString: "")
        tf.font = .systemFont(ofSize: 12, weight: .medium)
        tf.textColor = .labelColor
        tf.alignment = alignment
        tf.lineBreakMode = .byCharWrapping
        tf.maximumNumberOfLines = 0
        tf.usesSingleLineMode = false
        tf.preferredMaxLayoutWidth = maxWidth
        tf.cell?.truncatesLastVisibleLine = false
        tf.drawsBackground = false
        tf.isBezeled = false
        tf.isEditable = false
        tf.isSelectable = false
        return tf
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.stringValue = text
        nsView.alignment = alignment
        nsView.preferredMaxLayoutWidth = maxWidth
        nsView.invalidateIntrinsicContentSize()
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
