import SwiftUI

/// 应用外壳：顶部应用栏 + 左侧抽屉 + 内容区，承载整条导航栈。
struct SYRootShell: View {
    @StateObject private var state = SYAppState()

    var body: some View {
        NavigationStack(path: $state.path) {
            ZStack(alignment: .leading) {
                SYPalette.paper.ignoresSafeArea()

                content
                    .disabled(state.isDrawerOpen)

                if state.isDrawerOpen {
                    Color.black.opacity(0.26)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { closeDrawer() }
                        .transition(.opacity)
                        .zIndex(1)

                    SYDrawer(state: state)
                        .transition(.move(edge: .leading))
                        .zIndex(2)
                }
            }
            .animation(.easeOut(duration: 0.22), value: state.isDrawerOpen)
            .navigationDestination(for: SYRoute.self) { route in
                switch route {
                case .bookDetail(let book):
                    BookDetailView(book: book)
                case .reader(let book, let index):
                    ReaderView(book: book, startIndex: index)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(SYPalette.accent)
        .environmentObject(state)
        .onOpenURL { url in
            _ = state.handleDeepLink(url)
        }
        .overlay(alignment: .bottom) {
            if let notice = state.deepLinkNotice {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SYPalette.accent)
                    Text(notice)
                        .font(SYFont.callout.weight(.medium))
                        .foregroundStyle(SYPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, SYMetric.gapL)
                .padding(.vertical, 10)
                .background(SYPalette.surface, in: Capsule())
                .overlay(
                    Capsule().stroke(SYPalette.border, lineWidth: 0.8)
                )
                .shadow(color: SYPalette.ink.opacity(0.10), radius: 14, y: 5)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task(id: state.deepLinkNotice) {
            guard state.deepLinkNotice != nil else { return }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(.easeOut(duration: 0.25)) { state.deepLinkNotice = nil }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.section {
        case .bookshelf:
            BookshelfView(onMenu: openDrawer)
        case .discover:
            DiscoverView(onMenu: openDrawer)
        case .search:
            SearchView(onMenu: openDrawer)
        case .sources:
            BookSourceListView(onMenu: openDrawer)
        case .history:
            HistoryView(onMenu: openDrawer)
        case .settings:
            SettingsView(onMenu: openDrawer)
        }
    }

    private func openDrawer() {
        withAnimation(.easeOut(duration: 0.22)) { state.isDrawerOpen = true }
    }

    private func closeDrawer() {
        withAnimation(.easeOut(duration: 0.22)) { state.isDrawerOpen = false }
    }
}
