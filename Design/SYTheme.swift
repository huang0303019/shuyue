import SwiftUI
import UIKit

// MARK: - 颜色工具

extension UIColor {
    /// 以 0xRRGGBB 形式构造颜色。
    convenience init(syHex rgb: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

/// 书悦配色 Token —— 宣纸暖白底 / 松墨绿主色 / 旧金点缀，自成一套「纸上书卷」语言。
/// 与「閱讀」的 teal/orange 系统风、墨悦的珊瑚红卡片风均不相同。
enum SYPalette {
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(syHex: dark)
                : UIColor(syHex: light)
        })
    }

    static let paper = dyn(0xF5F0E6, 0x14120F)
    static let surface = dyn(0xFFFFFF, 0x1E1B17)
    static let surfaceAlt = dyn(0xEFE8DA, 0x262219)
    static let ink = dyn(0x1D1A16, 0xEDE7DC)
    static let inkSecondary = dyn(0x6B6355, 0xA79E8D)
    static let inkTertiary = dyn(0x9A9184, 0x6E675B)
    static let accent = dyn(0x2E6A52, 0x5FA383)
    static let accentSoft = dyn(0xE3EDE6, 0x233029)
    static let gold = dyn(0xB8863B, 0xC99A4E)
    static let danger = dyn(0xB23A48, 0xD06672)
    static let border = dyn(0xE2D9C8, 0x332E26)
}

/// 尺寸 Token。
enum SYMetric {
    static let gapXS: CGFloat = 4
    static let gapS: CGFloat = 8
    static let gapM: CGFloat = 12
    static let gapL: CGFloat = 16
    static let gapXL: CGFloat = 20
    static let gapXXL: CGFloat = 24
    static let gapHuge: CGFloat = 32

    static let radiusControl: CGFloat = 10
    static let radiusCard: CGFloat = 14
    static let radiusSheet: CGFloat = 20

    static let pagePadding: CGFloat = 16
    static let controlHeight: CGFloat = 40
    static let drawerWidth: CGFloat = 264
}

// MARK: - 阴影

extension View {
    /// 卡片投影：只用两级灰阶，不使用彩色投影。
    func syCardShadow() -> some View {
        shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    func syFloatShadow() -> some View {
        shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 6)
    }
}