import SwiftUI

// MARK: - 书源登录（loginUi 动态表单 + Cookie 保存 + loginCheckJs 校验）

/// Legado 风格登录面板：由书源 loginUi JSON 渲染动态表单（text/password/select/checkbox/toggle/button），
/// 提交后走书源 loginUrl（URL 模板填充或 POST 表单），Cookie 经 HTTPCookieStorage.shared 自动保存，
/// 配置 loginCheckJs 时对登录响应执行校验并给出通过/失败结论。
@MainActor
struct SourceLoginSheet: View {
    let source: SYBookSource

    @EnvironmentObject private var state: SYAppState
    @Environment(\.dismiss) private var dismiss

    @State private var ui: SYLoginUi?
    @State private var uiError: String?
    @State private var values: [String: String] = [:]
    @State private var selectedUrlIndex = 0
    @State private var isLoggingIn = false
    @State private var result: SYLoginResult?

    private var loginTitle: String {
        if let title = ui?.title, !title.isEmpty { return "登录：\(title)" }
        let name = source.bookSourceName.isEmpty ? "书源" : source.bookSourceName
        return "登录：\(name)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SYMetric.gapL) {
                    if let uiError {
                        hintBanner(uiError, tint: SYPalette.danger)
                    }

                    if let ui {
                        if ui.hasFields {
                            fieldsSection(ui.fields)
                        } else {
                            Text("该书源未定义登录表单字段，直接按登录地址发起请求。")
                                .font(SYFont.micro)
                                .foregroundStyle(SYPalette.inkTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(SYMetric.gapM)
                                .background(SYPalette.surfaceAlt, in: RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous))
                        }
                        if !ui.urls.isEmpty {
                            urlSelector(ui.urls)
                        }
                    } else if uiError == nil {
                        if source.loginUrl == nil || source.loginUrl!.isEmpty {
                            Text("该书源未配置登录地址（loginUrl），无法登录。")
                                .font(SYFont.callout)
                                .foregroundStyle(SYPalette.inkSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(SYMetric.gapM)
                                .background(SYPalette.surfaceAlt, in: RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous))
                        } else {
                            ProgressView()
                                .tint(SYPalette.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, SYMetric.gapL)
                        }
                    }

                    if let result {
                        resultBanner(result)
                    }

                    loginButton

                    Text("登录成功后的 Cookie 会自动保存；需在书源里开启「启用 Cookie」，后续搜索、详情请求才会携带。")
                        .font(SYFont.micro)
                        .foregroundStyle(SYPalette.inkTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(SYMetric.gapL)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(SYPalette.paper.ignoresSafeArea())
            .navigationTitle(loginTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await load() }
    }

    // MARK: - 表单字段

    @ViewBuilder
    private func fieldsSection(_ fields: [SYLoginField]) -> some View {
        VStack(spacing: SYMetric.gapS) {
            ForEach(fields) { field in
                fieldView(field)
            }
        }
    }

    @ViewBuilder
    private func fieldView(_ field: SYLoginField) -> some View {
        switch field.type {
        case .text, .input, .password, .captcha:
            inputField(field)
        case .select:
            if field.options.isEmpty {
                inputField(field)
            } else {
                selectField(field)
            }
        case .checkbox:
            checkboxField(field)
        case .toggle:
            toggleField(field)
        case .button:
            actionButtonField(field)
        case .label, .group:
            groupHeader(field)
        }
    }

    private func inputField(_ field: SYLoginField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(field.label)
                .font(SYFont.caption)
                .foregroundStyle(SYPalette.inkSecondary)
            HStack(spacing: SYMetric.gapS) {
                if field.type == .captcha {
                    Image(systemName: "rectangle.badge.checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SYPalette.accent)
                }
                Group {
                    if field.type == .password {
                        SecureField(field.type == .captcha ? "图形验证码" : "", text: binding(for: field.name))
                    } else {
                        TextField(field.type == .captcha ? "图形验证码" : "", text: binding(for: field.name))
                    }
                }
                .font(SYFont.body)
                .foregroundStyle(SYPalette.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }
            .padding(.horizontal, SYMetric.gapM)
            .frame(height: 44)
            .background(SYPalette.surface, in: RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous)
                    .stroke(SYPalette.border, lineWidth: 0.8)
            )
        }
    }

    private func selectField(_ field: SYLoginField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(field.label)
                .font(SYFont.caption)
                .foregroundStyle(SYPalette.inkSecondary)
            Picker(field.label, selection: binding(for: field.name)) {
                ForEach(field.options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .font(SYFont.body)
            .tint(SYPalette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SYMetric.gapM)
            .frame(height: 44)
            .background(SYPalette.surface, in: RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous)
                    .stroke(SYPalette.border, lineWidth: 0.8)
            )
        }
    }

    private func checkboxField(_ field: SYLoginField) -> some View {
        Toggle(isOn: boolBinding(for: field.name)) {
            Text(field.label)
                .font(SYFont.body)
                .foregroundStyle(SYPalette.ink)
        }
        .tint(SYPalette.accent)
        .padding(.horizontal, SYMetric.gapM)
        .frame(height: 48)
        .background(SYPalette.surface, in: RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous)
                .stroke(SYPalette.border, lineWidth: 0.8)
        )
    }

    private func toggleField(_ field: SYLoginField) -> some View {
        Toggle(isOn: boolBinding(for: field.name)) {
            Text(field.label)
                .font(SYFont.body)
                .foregroundStyle(SYPalette.ink)
        }
        .tint(SYPalette.accent)
        .padding(.horizontal, SYMetric.gapM)
        .frame(height: 48)
        .background(SYPalette.surface, in: RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous)
                .stroke(SYPalette.border, lineWidth: 0.8)
        )
    }

    private func actionButtonField(_ field: SYLoginField) -> some View {
        Button {
            result = SYLoginResult(
                success: false,
                message: "「\(field.label)」为脚本动作（action），当前版本暂不支持单独执行，请直接点下方「登录」。",
                checked: false
            )
        } label: {
            HStack(spacing: SYMetric.gapS) {
                Image(systemName: "bolt.horizontal")
                    .font(.system(size: 12, weight: .semibold))
                Text(field.label)
                    .font(SYFont.body.weight(.medium))
                    .foregroundStyle(SYPalette.accent)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(SYPalette.accentSoft, in: RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func groupHeader(_ field: SYLoginField) -> some View {
        Text(field.label)
            .font(SYFont.caption.weight(.semibold))
            .foregroundStyle(SYPalette.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, SYMetric.gapS)
    }

    // MARK: - 提交目标（对象形态 urls）

    private func urlSelector(_ urls: [SYLoginUrlAction]) -> some View {
        VStack(alignment: .leading, spacing: SYMetric.gapS) {
            Text("提交目标")
                .font(SYFont.caption)
                .foregroundStyle(SYPalette.inkSecondary)
            HStack(spacing: SYMetric.gapS) {
                ForEach(Array(urls.enumerated()), id: \.element.id) { index, action in
                    let active = index == selectedUrlIndex
                    Button {
                        selectedUrlIndex = index
                    } label: {
                        Text(action.name)
                            .font(SYFont.caption.weight(active ? .semibold : .regular))
                            .foregroundStyle(active ? Color.white : SYPalette.inkSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(active ? SYPalette.accent : SYPalette.surfaceAlt, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - 登录按钮与结果

    private var loginButton: some View {
        Button {
            performLogin()
        } label: {
            HStack(spacing: SYMetric.gapS) {
                if isLoggingIn {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "key.horizontal")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(isLoggingIn ? "正在登录" : "登录")
                    .font(SYFont.body.weight(.semibold))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                canLogin ? SYPalette.accent : SYPalette.inkTertiary.opacity(0.35),
                in: RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canLogin || isLoggingIn)
    }

    private func resultBanner(_ result: SYLoginResult) -> some View {
        HStack(alignment: .top, spacing: SYMetric.gapS) {
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(result.success ? SYPalette.accent : SYPalette.danger)
            Text(result.message)
                .font(SYFont.callout)
                .foregroundStyle(result.success ? SYPalette.ink : SYPalette.danger)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(SYMetric.gapM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (result.success ? SYPalette.accentSoft : SYPalette.danger.opacity(0.1)),
            in: RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous)
        )
    }

    private func hintBanner(_ text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: SYMetric.gapS) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(SYFont.callout)
                .foregroundStyle(SYPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(SYMetric.gapM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous))
    }

    // MARK: - 行为

    private var canLogin: Bool {
        if source.loginUrl == nil || source.loginUrl!.isEmpty {
            if let ui, !ui.urls.isEmpty { return true }
            return false
        }
        return true
    }

    private func load() async {
        guard ui == nil, uiError == nil else { return }
        guard let raw = source.loginUi, !raw.isEmpty else { return }
        if let loaded = await state.loadLoginUi(for: source) {
            ui = loaded
            var initial = values
            for field in loaded.fields {
                if let def = field.defaultValue, !def.isEmpty {
                    initial[field.name] = def
                }
            }
            values = initial
        } else {
            uiError = "登录界面解析失败：该书源 loginUi 可能由 JS 动态生成（依赖 java 桥），当前版本暂不支持。"
        }
    }

    private func performLogin() {
        guard !isLoggingIn, canLogin else { return }
        isLoggingIn = true
        result = nil
        Task {
            do {
                let urlAction: SYLoginUrlAction? = {
                    guard let ui, !ui.urls.isEmpty else { return nil }
                    return ui.urls[min(selectedUrlIndex, ui.urls.count - 1)]
                }()
                let loginResult = try await state.login(source: source, formValues: values, urlAction: urlAction)
                result = loginResult
            } catch {
                result = SYLoginResult(
                    success: false,
                    message: "登录失败：\(error.localizedDescription)",
                    checked: false
                )
            }
            isLoggingIn = false
        }
    }

    // MARK: - 绑定

    private func binding(for name: String) -> Binding<String> {
        Binding(
            get: { values[name] ?? "" },
            set: { values[name] = $0 }
        )
    }

    /// checkbox / toggle 的布尔绑定：值以 "true"/"false" 存储；toggle 双选项取第二项为开。
    private func boolBinding(for name: String) -> Binding<Bool> {
        Binding(
            get: {
                guard let value = values[name] else { return false }
                return value == "true" || value.lowercased() == "on" || value == "1"
            },
            set: { isOn in
                values[name] = isOn ? "true" : "false"
            }
        )
    }
}

#Preview("登录表单") {
    SourceLoginSheet(
        source: SYBookSource(
            bookSourceName: "示例书源",
            bookSourceUrl: "https://example.com",
            loginUrl: "https://example.com/login",
            loginUi: #"[{"name":"username","type":"text","viewName":"'用户名'"},{"name":"password","type":"password","viewName":"'密码'"},{"name":"remember","type":"checkbox","viewName":"'记住我'","default":"true"}]"#,
            loginCheckJs: "js:result.contains('欢迎')"
        )
    )
}

#Preview("对象形态") {
    SourceLoginSheet(
        source: SYBookSource(
            bookSourceName: "多接口书源",
            bookSourceUrl: "https://example.com",
            loginUi: #"{"title":"账号登录","params":[{"name":"account","type":"text","label":"账号"}],"urls":[{"name":"登录","url":"https://example.com/login","method":"POST"}]}"#,
            loginCheckJs: "js:result.contains('ok')"
        )
    )
}
