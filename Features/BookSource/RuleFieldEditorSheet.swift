import Combine
import SwiftUI
import UIKit

// MARK: - 规则字段底部编辑器

/// 单字段规则编辑器：等宽文本编辑 + 上方可横向滚动的规则插入 chips。
/// 点按 chip 在光标处插入规则片段，复刻 Legado 键盘辅助栏的常用输入体验。
@MainActor
struct RuleFieldEditorSheet: View {
    let title: String
    let helpText: String?
    let initialValue: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @StateObject private var bridge = SYRuleTextViewBridge()

    /// 与 Legado 默认 keyboardAssists.json 对齐的常用片段。
    private static let insertChips: [String] = [
        "@css:", "@js:", "@XPath:", "@webjs:", "@Json:", "<js></js>",
        "{{}}", "##", "&&", "%%", "||", "//", "$.",
        "@text", "@href", "@src", "@alt", "@html",
        "textNodes", "ownText", "all", #",{"webView": true}"#
    ]

    init(title: String, helpText: String?, initialValue: String, onSave: @escaping (String) -> Void) {
        self.title = title
        self.helpText = helpText
        self.initialValue = initialValue
        self.onSave = onSave
        _text = State(initialValue: initialValue)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                chipBar
                Divider()
                SYRuleTextView(
                    text: $text,
                    font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                    bridge: bridge
                )
                .padding(.horizontal, SYMetric.gapM)
                .padding(.top, SYMetric.gapS)
                if let helpText {
                    Text(helpText)
                        .font(SYFont.micro)
                        .foregroundStyle(SYPalette.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, SYMetric.gapM)
                        .padding(.top, SYMetric.gapS)
                }
                Spacer(minLength: 0)
            }
            .background(SYPalette.paper.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button {
                        onSave(text)
                        dismiss()
                    } label: {
                        Text("完成").fontWeight(.semibold)
                    }
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("清空")
                }
            }
            .onAppear {
                bridge.textView?.becomeFirstResponder()
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// 规则插入辅助栏。
    private var chipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SYMetric.gapXS) {
                ForEach(Self.insertChips, id: \.self) { chip in
                    Button {
                        insert(chip)
                    } label: {
                        Text(chip)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(SYPalette.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(SYPalette.accentSoft, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(chip)
                }
            }
            .padding(.horizontal, SYMetric.gapM)
            .padding(.vertical, SYMetric.gapXS)
        }
        .background(SYPalette.surfaceAlt)
        .accessibilityLabel("规则插入")
    }

    private func insert(_ chip: String) {
        if let textView = bridge.textView {
            textView.insertText(chip)
        } else {
            text += chip
        }
    }
}

// MARK: - UITextView Bridge

/// 共享底层 UITextView 引用，使 chips 能在实时光标处插入文本
/// （SwiftUI `TextEditor` 不暴露选区 API）。
@MainActor
final class SYRuleTextViewBridge: @preconcurrency ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    weak var textView: UITextView?
}

/// 等宽 `UITextView`：双向同步 text，并把视图暴露给 bridge 做光标插入。
private struct SYRuleTextView: UIViewRepresentable {
    @Binding var text: String
    let font: UIFont
    let bridge: SYRuleTextViewBridge

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = font
        textView.backgroundColor = .clear
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.text = text
        textView.delegate = context.coordinator
        bridge.textView = textView
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        bridge.textView = uiView
        // 仅当值从外部变化（如清空）时重写，逐键重写会重置光标。
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SYRuleTextView

        init(_ parent: SYRuleTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
    }
}
