import AppKit
import SwiftUI

/// 搜索框自己画底色，不用系统焦点环。
struct SearchBar: View {
    @Binding var text: String
    @State private var focused = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            QuietTextField(text: $text, focused: $focused, placeholder: "搜索歌曲、歌手")
                .frame(height: 18)
            Button {
                NSApp.keyWindow?.makeFirstResponder(nil)
                text = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(text.isEmpty ? 0 : 1)
            .allowsHitTesting(!text.isEmpty)
            .help("清除")
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(focused ? 0.09 : 0.05))
        )
        .focusEffectDisabled()
    }
}

private struct QuietTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, focused: $focused)
    }

    func makeNSView(context: Context) -> LineSearchTextView {
        let view = LineSearchTextView(frame: .zero, textContainer: nil)
        view.delegate = context.coordinator
        view.placeholder = placeholder
        view.string = text
        return view
    }

    func updateNSView(_ view: LineSearchTextView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.focused = $focused
        view.placeholder = placeholder
        let editing = view.hasMarkedText() || view.window?.firstResponder === view
        guard !editing, view.string != text else { return }
        view.string = text
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var focused: Binding<Bool>

        init(text: Binding<String>, focused: Binding<Bool>) {
            self.text = text
            self.focused = focused
        }

        func textDidBeginEditing(_ notification: Notification) {
            focused.wrappedValue = true
        }

        func textDidEndEditing(_ notification: Notification) {
            focused.wrappedValue = false
            publish(notification)
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView, !view.hasMarkedText() else { return }
            let value = view.string
            // 等这次按键和输入法组字结束，再刷新列表，避免第一个字母被界面重绘清掉。
            DispatchQueue.main.async { [weak self] in
                guard let self, self.text.wrappedValue != value else { return }
                self.text.wrappedValue = value
            }
        }

        private func publish(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            if text.wrappedValue != view.string {
                text.wrappedValue = view.string
            }
        }
    }
}

/// 单行文本视图。输入法的标记文本由它自己保存，不经过 NSTextField 的字段编辑器。
final class LineSearchTextView: NSTextView {
    var placeholder = "" {
        didSet {
            if oldValue != placeholder { needsDisplay = true }
        }
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: 18))
        storage.addLayoutManager(layout)
        layout.addTextContainer(textContainer)
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.maximumNumberOfLines = 1
        textContainer.lineFragmentPadding = 0
        super.init(frame: frameRect, textContainer: textContainer)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        drawsBackground = false
        backgroundColor = .clear
        isRichText = false
        importsGraphics = false
        isEditable = true
        isSelectable = true
        allowsUndo = true
        usesFindPanel = false
        usesFontPanel = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        enabledTextCheckingTypes = 0
        focusRingType = .none
        insertionPointColor = .labelColor
        font = .systemFont(ofSize: 13)
        textColor = .labelColor
        textContainerInset = NSSize(width: 0, height: 1)
        isHorizontallyResizable = false
        isVerticallyResizable = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    override func insertNewline(_ sender: Any?) {
        window?.makeFirstResponder(nil)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText() else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.placeholderTextColor
        ]
        let rect = NSRect(x: textContainerInset.width, y: 0, width: bounds.width, height: bounds.height)
        placeholder.draw(in: rect, withAttributes: attributes)
    }
}
