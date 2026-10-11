import SwiftUI

@main
struct ShuYueApp: App {
    var body: some Scene {
        WindowGroup {
            SYRootShell()
                .accentColor(SYPalette.accent)
        }
    }
}