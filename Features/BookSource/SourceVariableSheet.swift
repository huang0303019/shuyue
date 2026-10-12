import SwiftUI

// MARK: - 设置源变量（source.getVariable()）

/// Legado 风格「设置源变量」面板：上方为书源作者的 `variableComment` 说明区，
/// 下方为等宽 JSON 文本编辑区，保存后书源 JS 通过 `source.getVariable()` 读取。
/// 说明区为空时仅显示用法提示（与墨悦 / Legado 的 displayComment 行为一致）。
@MainActor
struct SourceVariableSheet: View {
    let source: SYBookSource
    let onSave: (SYBookSource) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    /// 说明区：书源作者的 variableComment（非空时）+ 用法提示。
    private var comment: String {
        let own = (source.variableComment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hint = "源变量为 JSON 文本，可在书源 JS 中通过 source.getVariable() 读取。"
        return own.isEmpty ? hint : "\(own)\n\(hint)"
    }

    init(source: SYBookSource, onSave: @escaping (SYBookSource) -> Void) {
        self.source = source
        self.onSave = onSave
        _text = State(initialValue: source.variable ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !comment.isEmpty {
                    Text(comment)
                        .font(SYFont.micro)
                        .foregroundStyle(SYPalette.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.horizontal, SYMetric.gapM)
                        .padding(.vertical, SYMetric.gapS)
                        .background(SYPalette.surfaceAlt)
                }
                Divider()
                TextEditor(text: $text)
                    .font(.system(size: 14, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, SYMetric.gapM)
                    .padding(.top, SYMetric.gapS)
                Spacer(minLength: 0)
            }
            .background(SYPalette.paper.ignoresSafeArea())
            .navigationTitle("设置源变量")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button {
                        save()
                        dismiss()
                    } label: {
                        Text("保存").fontWeight(.semibold)
                    }
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("清空")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        var updated = source
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.variable = trimmed.isEmpty ? nil : trimmed
        onSave(updated)
    }
}

#Preview("源变量说明") {
    SourceVariableSheet(
        source: SYBookSource(
            bookSourceName: "示例书源",
            bookSourceUrl: "https://example.com",
            variable: #"{"apiKey":""}"#,
            variableComment: "填入你的 API Key（含 Bearer 前缀）"
        ),
        onSave: { _ in }
    )
}

#Preview("无说明") {
    SourceVariableSheet(
        source: SYBookSource(bookSourceName: "示例书源", bookSourceUrl: "https://example.com"),
        onSave: { _ in }
    )
}