import SwiftUI

/// 书房 —— 书悦的核心页面：分组胶囊页签 + 书脊卡片书架。
/// 点击卡片进入书籍详情，长按可移动分组或移出书架。
@MainActor
struct BookshelfView: View {
    let onMenu: () -> Void

    @EnvironmentObject private var state: SYAppState

    @State private var group: String = "全部"
    private let groups = ["全部", "在读", "想读", "已读"]
    private let shelfTints: [Color] = [SYPalette.accent, SYPalette.gold]

    var body: some View {
        SYScreen(title: "书房", subtitle: "共 \(state.shelf.count) 本", onMenu: onMenu) {
            SYCapsuleTabs(items: groups, label: { $0 }, selection: $group)
                .padding(.horizontal, -SYMetric.pagePadding)

            if filteredItems.isEmpty {
                SYEmptyState(
                    systemImage: "books.vertical",
                    title: state.shelf.isEmpty ? "书架还空着" : "没有「\(group)」中的书",
                    message: state.shelf.isEmpty
                        ? "去「书源」导入 Legado 书源，搜索想读的书加入书架，它们会以书脊卡片排在这里。"
                        : "切回「全部」可查看全部书籍，或在详情页中移动分组。",
                    actionTitle: state.shelf.isEmpty ? "去书源" : nil,
                    action: state.shelf.isEmpty ? { state.present(.sources) } : nil
                )
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: SYMetric.gapL), GridItem(.flexible(), spacing: SYMetric.gapL)],
                    spacing: SYMetric.gapL
                ) {
                    ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                        SYSpineCard(
                            title: item.book.name,
                            author: subtitle(for: item),
                            progress: item.progress,
                            tint: shelfTints[index % shelfTints.count]
                        )
                        .onTapGesture { state.open(.bookDetail(item.book)) }
                        .contextMenu { shelfMenu(for: item) }
                    }
                }
            }
        }
    }

    private var filteredItems: [SYBookshelfItem] {
        if group == "全部" { return state.shelf }
        return state.shelf.filter { $0.group == group }
    }

    private func subtitle(for item: SYBookshelfItem) -> String? {
        var parts: [String] = []
        if let author = item.book.author, !author.isEmpty { parts.append(author) }
        if let chapterTitle = item.chapterTitle, !chapterTitle.isEmpty, item.chapterIndex > 0 {
            parts.append(chapterTitle)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func shelfMenu(for item: SYBookshelfItem) -> some View {
        ForEach(groups.filter { $0 != "全部" && $0 != item.group }, id: \.self) { g in
            Button {
                state.setGroup(g, for: item.book)
            } label: {
                Label("移到「\(g)」", systemImage: "folder")
            }
        }
        Button(role: .destructive) {
            state.removeFromShelf(item.book)
        } label: {
            Label("移出书架", systemImage: "trash")
        }
    }
}