import SwiftUI

/// 字体阶 —— 标题走衬线族营造书卷感，正文与控件用系统字体。
enum SYFont {
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static let appTitle = serif(24, .bold)
    static let screenTitle = serif(22, .bold)
    static let sectionTitle = serif(18, .semibold)
    static let bookTitle = serif(16, .semibold)

    static let body = Font.system(size: 15)
    static let callout = Font.system(size: 14)
    static let caption = Font.system(size: 12)
    static let micro = Font.system(size: 11)
}