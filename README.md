# 书悦 ShuYue

> 一款**全新原创**的 iOS 开源阅读器，兼容 Legado / 阅读 3.0 书源规范。

书悦从零设计与实现：全新的信息架构、自研的书源规则引擎、自绘的界面组件。你可以在其中导入 Legado 书源，搜索书籍、加入书架并离线阅读。

## 特性

- **兼容 Legado 书源**：支持 `@json:` / `@css:` / `@XPath:` / `@js:` 规则、`||` 回退、`##` 替换、`{{ }}` 模板与书源变量。
- **原生体验**：SwiftUI 编写，零第三方依赖；使用系统 JavaScriptCore 执行书源 JS。
- **原创界面**：取消底部标签栏，采用顶部应用栏 + 左侧抽屉的书房式导航；宣纸暖白 / 松墨绿 / 旧金的"纸上书卷"视觉语言。
- **完整链路**：导入书源 → 搜索 → 加入书架 → 目录 → 阅读，一气呵成。

## 截图

_待补充_

## 构建

需要 Xcode 15/16 与 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
brew install xcodegen
xcodegen generate
open ShuYue.xcodeproj
```

工程最低支持 iOS 16.0，使用标准 `xcodebuild` 即可构建：

```bash
xcodebuild -project ShuYue.xcodeproj -scheme ShuYue -configuration Release -sdk iphoneos \
  CODE_SIGNING_ALLOWED=NO build
```

仓库内的 GitHub Actions 会自动构建**无签名 IPA**，产物见 [Releases](../../releases)。

## 许可

本项目以 MPL-2.0 许可开源，详见 [LICENSE](LICENSE)。

书悦与「閱讀」「Legado」等项目无从属关系，书源内容由使用者自行导入并自负其责。

## 文档

- 产品与工程规格：[docs/DESIGN.md](docs/DESIGN.md)