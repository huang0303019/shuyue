import SwiftUI

/// 阅读历史 —— 按时间倒序展示最近读过的书，支持一键清空。
@MainActor
struct HistoryView: View {
    let onMenu: () -> Void

    @EnvironmentObject private var state: SYAppState

    @State private var showClearConfirm = false

    var body: some View {
        SYScreen(
            title: "阅读历史",
            subtitle: state.history.isEmpty ? "最近读过的书" : "共 \(state.history.count) 条记录",
            onMenu: onMenu,
            trailing: {
                if !state.history.isEmpty {
                    Button {
                        showClearConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SYPalette.ink)
                            .frame(width: 38, height: 38)
                            .background(SYPalette.surfaceAlt, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空历史")
                }
            }
        ) {
            if state.history.isEmpty {
                SYEmptyState(
                    systemImage: "clock.arrow.circlepath",
                    title: "还没有阅读记录",
                    message: "开始阅读后，这里会按时间倒序记录你的阅读轨迹。"
                )
            } else {
                VStack(spacing: SYMetric.gapM) {
                    ForEach(state.history) { entry in
                        SYBookRow(
                            book: entry.book,
                            subtitle: subtitle(for: entry),
                            progress: progress(for: entry)
                        ) {
                            state.open(.bookDetail(entry.book))
                        }
                    }
                }
            }
        }
        .confirmationDialog("确定清空全部阅读历史？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空历史", role: .destructive) {
                state.clearHistory()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func subtitle(for entry: SYHistoryEntry) -> String {
        var parts: [String] = [dateText(entry.date)]
        if let chapterTitle = entry.chapterTitle, !chapterTitle.isEmpty {
            parts.append(chapterTitle)
        }
        return parts.joined(separator: " · ")
    }

    private func progress(for entry: SYHistoryEntry) -> Double? {
        guard let item = state.shelfItem(for: entry.book), item.progress > 0 else { return nil }
        return item.progress
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}