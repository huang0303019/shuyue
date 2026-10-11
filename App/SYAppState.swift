import SwiftUI

/// 全局界面状态。数据层（书源 / 书架 / 设置）将在后续里程碑接入。
final class SYAppState: ObservableObject {
    @Published var section: SYSection = .bookshelf
    @Published var isDrawerOpen = false

    func present(_ section: SYSection) {
        self.section = section
        isDrawerOpen = false
    }

    func toggleDrawer() {
        isDrawerOpen.toggle()
    }
}