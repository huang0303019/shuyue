import SwiftUI

/// 阅读器 —— 正文展示、翻章、目录跳转、主题与字体设置、进度记录。
/// 点按正文中间区域切换控制栏，左右滑动可翻章。
@MainActor
struct ReaderView: View {
    let book: SYBook
    var startIndex: Int? = nil

    @EnvironmentObject private var state: SYAppState
    @Environment(\.dismiss) private var dismiss

    @State private var chapters: [SYChapter] = []
    @State private var currentIndex = 0
    @State private var content = ""
    @State private var contentCache: [Int: String] = [:]
    @State private var isLoading = false
    @State private var loadError: String?

    @State private var hasInitialized = false
    @State private var showControls = true
    @State private var showTOC = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                if showControls {
                    topBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                contentArea
                    .opacity(isLoading && !content.isEmpty ? 0.65 : 1)

                if showControls {
                    bottomBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            if showSettings {
                settingsPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: showControls)
        .animation(.easeOut(duration: 0.2), value: showSettings)
        .toolbar(.hidden, for: .navigationBar)
        .task { await initialize() }
        .sheet(isPresented: $showTOC) { tocSheet }
    }

    // MARK: - 派生状态

    private var theme: ReaderTheme { state.settings.theme }
    private var settings: SYReaderSettings { state.settings }

    private var chapterTitle: String {
        guard currentIndex < chapters.count else { return book.name }
        return chapters[currentIndex].title
    }

    private var progressText: String {
        guard !chapters.isEmpty else { return "" }
        return "\(currentIndex + 1)/\(chapters.count)"
    }

    private var contentFont: Font {
        settings.useSerif
            ? .system(size: settings.fontSize, design: .serif)
            : .system(size: settings.fontSize)
    }

    private var paragraphs: [String] {
        content
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private var paragraphGap: CGFloat { max(4, min(12, settings.lineSpacing * 0.9)) }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: SYMetric.gapM) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.controlsText)
                    .frame(width: 38, height: 38)
                    .background(theme.controlsText.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("退出阅读")

            Text(chapterTitle)
                .font(SYFont.callout.weight(.medium))
                .foregroundStyle(theme.controlsText)
                .lineLimit(1)

            Spacer(minLength: SYMetric.gapS)

            Text(progressText)
                .font(SYFont.micro)
                .foregroundStyle(theme.controlsText.opacity(0.6))
        }
        .padding(.horizontal, SYMetric.gapM)
        .frame(minHeight: 50)
        .background(theme.controlsBackground)
        .overlay(
            Rectangle()
                .fill(theme.controlsText.opacity(0.06))
                .frame(height: 0.8),
            alignment: .bottom
        )
    }

    // MARK: - 正文区

    @ViewBuilder
    private var contentArea: some View {
        if isLoading && content.isEmpty {
            VStack(spacing: SYMetric.gapM) {
                ProgressView()
                    .tint(theme.controlsText.opacity(0.7))
                Text("正在加载正文")
                    .font(SYFont.callout)
                    .foregroundStyle(theme.controlsText.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if content.isEmpty, let loadError {
            VStack(spacing: SYMetric.gapM) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(theme.controlsText.opacity(0.7))
                Text("正文加载失败")
                    .font(SYFont.sectionTitle)
                    .foregroundStyle(theme.controlsText)
                Text(loadError)
                    .font(SYFont.caption)
                    .foregroundStyle(theme.controlsText.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                SYButton(title: "重试", kind: .secondary) {
                    Task { await loadChapter(at: currentIndex) }
                }
                .frame(maxWidth: 220)
            }
            .padding(SYMetric.gapXL)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(chapterTitle)
                        .font(SYFont.serif(17, .bold))
                        .foregroundStyle(theme.textColor.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, SYMetric.gapL)

                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, para in
                        if para.isEmpty {
                            Color.clear
                                .frame(height: max(6, paragraphGap))
                        } else {
                            Text(para)
                                .font(contentFont)
                                .foregroundStyle(theme.textColor)
                                .lineSpacing(settings.lineSpacing)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, paragraphGap)
                        }
                    }

                    Color.clear
                        .frame(height: SYMetric.gapHuge * 2)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, SYMetric.gapHuge)
                .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleControls() }
            .gesture(swipeGesture)
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 30, coordinateSpace: .local)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 60, abs(dx) > abs(dy) * 1.5 else { return }
                if dx < 0 {
                    goNext()
                } else {
                    goPrev()
                }
            }
    }

    // MARK: - 底栏

    private var bottomBar: some View {
        HStack(spacing: SYMetric.gapM) {
            barButton("list.bullet", accessibility: "目录") {
                showTOC = true
                showSettings = false
            }

            barButton("textformat.size", accessibility: "阅读设置") {
                withAnimation(.easeOut(duration: 0.2)) {
                    showSettings.toggle()
                }
            }

            Spacer(minLength: SYMetric.gapS)

            barButton("chevron.left", accessibility: "上一章", enabled: currentIndex > 0) {
                goPrev()
            }

            Text(progressText)
                .font(SYFont.micro)
                .foregroundStyle(theme.controlsText.opacity(0.6))
                .frame(minWidth: 46)

            barButton("chevron.right", accessibility: "下一章", enabled: currentIndex < chapters.count - 1) {
                goNext()
            }
        }
        .padding(.horizontal, SYMetric.gapM)
        .frame(minHeight: 52)
        .background(theme.controlsBackground)
        .overlay(
            Rectangle()
                .fill(theme.controlsText.opacity(0.06))
                .frame(height: 0.8),
            alignment: .top
        )
    }

    private func barButton(
        _ systemName: String,
        accessibility: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.controlsText)
                .frame(width: 40, height: 40)
                .background(theme.controlsText.opacity(0.08), in: Circle())
                .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }

    // MARK: - 阅读设置面板

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: SYMetric.gapL) {
            HStack {
                Text("阅读设置")
                    .font(SYFont.sectionTitle)
                    .foregroundStyle(theme.controlsText)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showSettings = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.controlsText)
                        .frame(width: 30, height: 30)
                        .background(theme.controlsText.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭设置")
            }

            Text("主题")
                .font(SYFont.caption)
                .foregroundStyle(theme.controlsText.opacity(0.6))

            HStack(spacing: SYMetric.gapL) {
                ForEach(ReaderTheme.allCases) { item in
                    themeButton(item)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: SYMetric.gapM) {
                Text("A")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.controlsText.opacity(0.6))
                Slider(value: fontSizeBinding, in: 13...30, step: 1)
                    .tint(SYPalette.accent)
                Text("A")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(theme.controlsText.opacity(0.6))
            }

            HStack(spacing: SYMetric.gapM) {
                Image(systemName: "arrow.up.and.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.controlsText.opacity(0.6))
                Slider(value: lineSpacingBinding, in: 2...20, step: 1)
                    .tint(SYPalette.accent)
                Text("间距")
                    .font(SYFont.caption)
                    .foregroundStyle(theme.controlsText.opacity(0.6))
                    .frame(width: 36, alignment: .trailing)
            }

            Toggle(isOn: serifBinding) {
                Text("衬线字体")
                    .font(SYFont.callout)
                    .foregroundStyle(theme.controlsText)
            }
            .tint(SYPalette.accent)
        }
        .padding(SYMetric.gapXL)
        .background(
            theme.controlsBackground,
            in: RoundedRectangle(cornerRadius: SYMetric.radiusSheet, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SYMetric.radiusSheet, style: .continuous)
                .stroke(theme.controlsText.opacity(0.1), lineWidth: 0.8)
        )
        .padding(.horizontal, SYMetric.pagePadding)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func themeButton(_ item: ReaderTheme) -> some View {
        let selected = item == theme
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { state.setTheme(item) }
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(item.background)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .stroke(selected ? SYPalette.accent : theme.controlsText.opacity(0.15), lineWidth: selected ? 3 : 1)
                    )
                Text(item.title)
                    .font(SYFont.micro.weight(selected ? .semibold : .regular))
                    .foregroundStyle(theme.controlsText)
            }
        }
        .buttonStyle(.plain)
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { state.settings.fontSize },
            set: { state.setFontSize($0) }
        )
    }

    private var lineSpacingBinding: Binding<Double> {
        Binding(
            get: { state.settings.lineSpacing },
            set: { state.setLineSpacing($0) }
        )
    }

    private var serifBinding: Binding<Bool> {
        Binding(
            get: { state.settings.useSerif },
            set: { state.setUseSerif($0) }
        )
    }

    // MARK: - 目录页

    private var tocSheet: some View {
        NavigationStack {
            Group {
                if chapters.isEmpty {
                    SYEmptyState(
                        systemImage: "list.bullet",
                        title: "没有章节",
                        message: "目录解析为空，请返回详情页重试。"
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                                tocRow(chapter)

                                if index < chapters.count - 1 {
                                    Divider()
                                        .overlay(SYPalette.border)
                                        .padding(.leading, SYMetric.gapL)
                                }
                            }
                        }
                        .padding(.vertical, SYMetric.gapS)
                    }
                }
            }
            .background(SYPalette.paper.ignoresSafeArea())
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showTOC = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func tocRow(_ chapter: SYChapter) -> some View {
        Button {
            showTOC = false
            Task { await loadChapter(at: chapter.index) }
        } label: {
            HStack(spacing: SYMetric.gapS) {
                Text(chapter.title)
                    .font(SYFont.body)
                    .foregroundStyle(chapter.index == currentIndex ? SYPalette.accent : SYPalette.ink)
                    .lineLimit(1)
                if chapter.isVip {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(SYPalette.gold)
                }
                Spacer(minLength: SYMetric.gapXS)
                if chapter.index == currentIndex {
                    Text("当前")
                        .font(SYFont.micro.weight(.semibold))
                        .foregroundStyle(SYPalette.accent)
                }
            }
            .padding(.horizontal, SYMetric.gapL)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 控制栏 / 翻章

    private func toggleControls() {
        withAnimation(.easeOut(duration: 0.2)) {
            showControls.toggle()
            showSettings = false
        }
    }

    private func goPrev() {
        guard currentIndex > 0 else { return }
        Task { await loadChapter(at: currentIndex - 1) }
    }

    private func goNext() {
        guard currentIndex < chapters.count - 1 else { return }
        Task { await loadChapter(at: currentIndex + 1) }
    }

    // MARK: - 初始化与加载

    @MainActor
    private func initialize() async {
        guard !hasInitialized else { return }
        hasInitialized = true

        if chapters.isEmpty {
            do {
                chapters = try await state.chapters(for: book)
            } catch {
                loadError = error.localizedDescription
                return
            }
        }

        if let startIndex {
            currentIndex = min(max(0, startIndex), max(0, chapters.count - 1))
        } else if let item = state.shelfItem(for: book), item.chapterIndex < chapters.count {
            currentIndex = max(0, item.chapterIndex)
        }

        await loadChapter(at: currentIndex)
    }

    @MainActor
    private func loadChapter(at index: Int) async {
        guard !chapters.isEmpty, index >= 0, index < chapters.count else { return }
        currentIndex = index

        if let cached = contentCache[index] {
            content = cached
            recordProgress()
            return
        }

        isLoading = true
        loadError = nil
        do {
            let text = try await state.content(for: chapters[index])
            content = text
            contentCache[index] = text
            recordProgress()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func recordProgress() {
        guard currentIndex < chapters.count else { return }
        state.updateProgress(
            book: book,
            chapterIndex: currentIndex,
            chapterTitle: chapters[currentIndex].title,
            chapterCount: chapters.count
        )
    }
}