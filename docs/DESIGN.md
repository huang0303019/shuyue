# 书悦 ShuYue — 产品与工程规格

> 本文件是书悦从零实现的唯一依据。目标是交付一款**全新原创**的 iOS 开源阅读软件，兼容 Legado 书源规范，并在界面、信息架构、组件风格上与「閱讀」及墨悦明显不同，杜绝套壳观感。

## 1. 命名与标识

| 项 | 取值 |
| --- | --- |
| 应用名（中文） | 书悦 |
| 应用名（英文显示名） | ShuYue |
| 仓库名 | `ShuYue`（zhong228/ShuYue，public） |
| Bundle ID | `com.zhong228.shuyue` |
| 代码命名空间 | `SY` 前缀（SYTheme / SYEngine / SYStore …），不沿用任何 `yuedu`/`閱讀`/`MoYue` 标识符 |
| 许可证 | MPL-2.0（全新原创代码，可独立更换） |
| 最低系统 | iOS 16.0 |
| 语言 | Swift 5.9+ / SwiftUI，零第三方依赖（系统框架 JavaScriptCore、WebKit、UIKit 集成） |

## 2. 与「閱讀」/墨悦的差异（逐条）

1. **导航模型**：閱讀/墨悦用底部 `UITabBar`（书架/发现/搜索/我的等多顶级标签）；书悦**取消底部标签栏**，改为「顶部应用栏 + 左侧抽屉（Drawer）」主导航。
2. **视觉基调**：閱讀偏 teal/orange 系统风，墨悦为珊瑚红→靛蓝的现代卡片风；书悦走**宣纸暖白 + 松墨绿主色 + 旧金点缀 + 衬线标题**的"纸上书卷"气质。
3. **信息架构**：墨悦把发现、搜索、订阅、AI 等平铺成多个顶级入口；书悦以**「书房」为唯一中心**，其余（发现/搜索/书源/历史/设置）收进抽屉，削减顶级入口。
4. **组件语言**：墨悦用 `HostedCollectionList` + 会话式卡片行；书悦自绘**书脊卡片、顶部胶囊分组页签、右下悬浮操作球**，圆角与投影自成一套。
5. **书架呈现**：墨悦为网格/列表切换 + 文件夹分组；书悦默认**"书脊架"两列卡片**，卡片底部带进度"书签线"，分组用顶部胶囊页签切换。
6. **阅读器**：墨悦为分页/滚动 + 大量 Pro 主题；书悦自研 `SYReader`，**翻页 / 滚动**两模式 + 极简页眉页脚与右上进度环，内置**宣纸 / 夜墨 / 护眼**三套原创主题。
7. **标识体系**：全新应用名、图标、Bundle ID、命名空间，仓库内不出现上游任何文件名与符号。
8. **代码结构**：全新目录划分（App/Design/Model/Engine/Store/Features/Resources），不复制上游文件，实现从零编写。

## 3. 信息架构与页面清单

- **SYRootShell**：顶部应用栏（左：抽屉按钮；中：衬线大标题；右：搜索/更多）＋ 左侧抽屉 ＋ 内容区 ＋ 右下悬浮「＋」。
- **书房 Bookshelf**：分组胶囊页签（全部/在读/想读/已读/自定义分组）＋ 书脊卡片网格（列表可切换）＋ 长按菜单（详情/换源/分组/移除）。
- **书籍详情 BookDetail**：封面色块、书名/作者/来源、简介折叠、目录预览、加入书架、换源。
- **阅读器 Reader**：正文排版（翻页/滚动）、点击中部呼出菜单、目录抽屉、字号/行距/主题、进度环、章节切换。
- **发现 Discover**：按书源发现页抓取分类/推荐，横向卡片流；可切书源。
- **搜索 Search**：跨书源并发搜索、结果聚合、一键加入书架。
- **书源管理 Sources**：分组折叠列表、启用开关、类型徽标、校验、导入/导出、编辑、单人调试。
- **书源编辑 SourceEdit**：字段表单 ＋ 规则调试（输入关键词试抓）。
- **历史 History**：最近阅读记录。
- **设置 Settings**：阅读设置、外观、Legado 兼容说明、开源许可、关于。

## 4. 设计语言

**配色 Token（浅色 / 深色）**

| Token | 浅色 | 深色 | 用途 |
| --- | --- | --- | --- |
| paper | `#F5F0E6` | `#14120F` | 页面底色 |
| surface | `#FFFFFF` | `#1E1B17` | 卡片/浮层 |
| surfaceAlt | `#EFE8DA` | `#262219` | 次级容器 |
| ink | `#1D1A16` | `#EDE7DC` | 主文字 |
| inkSecondary | `#6B6355` | `#A79E8D` | 次文字 |
| inkTertiary | `#9A9184` | `#6E675B` | 弱文字 |
| accent（松墨绿） | `#2E6A52` | `#5FA383` | 主色 |
| accentSoft | `#E3EDE6` | `#233029` | 主色浅底 |
| gold（旧金） | `#B8863B` | `#C99A4E` | 点缀/强调 |
| danger | `#B23A48` | `#D06672` | 危险操作 |
| border | `#E2D9C8` | `#332E26` | 描边 |

**字体**：正文与控件用系统字体（`SF`）；页面大标题、书籍标题用**衬线族**（`.system(design: .serif)`），营造书卷感。字号阶：11/12/13/15/17/20/24/30。

**尺度**：间距 4/8/12/16/20/24/32；圆角 10/14/20/capsule；投影只用两级（卡片 `#000` 6% / 浮层 12%），不使用彩色投影。

**组件库（SYComponents）**：`SYTopBar`、`SYDrawer`、`SYCapsuleTabs`、`SYSpineCard`、`SYRowCard`、`SYChip`、`SYPillToggle`、`SYButton`、`SYFloatingAction`、`SYEmptyState`、`SYProgressRing`、`SYSheet`、`SYToast`。

## 5. 模块划分（目录结构）

```
ShuYue/
  project.yml                 # XcodeGen 工程定义
  App/                        # ShuYueApp(@main)、AppEnvironment、SYRootShell、抽屉与顶栏
  Design/                     # SYTheme、SYTypography、SYComponents/*
  Model/                      # BookSource、RuleSet、SearchBook、BookDetail、Chapter、ShelfBook、ReadRecord
  Engine/                     # RuleEngine、规则语法、JSONPath 子集、XPath/CSS 适配、JSContext 宿主、HTTP、字符集
  Store/                      # LibraryStore(actor)、SourceStore、SettingsStore、JSON 持久化
  Features/                   # Bookshelf / BookDetail / Reader / Discover / Search / Source / History / Settings
  Resources/                  # Assets.xcassets、PrivacyInfo.xcprivacy
  docs/DESIGN.md
  .github/workflows/build.yml
  scripts/build_ipa.sh
  README.md  LICENSE  .gitignore  project.yml
```

## 6. Legado 兼容范围

**书源级字段**：`bookSourceUrl`、`bookSourceName`、`bookSourceGroup`、`bookSourceType`、`bookSourceComment`、`customOrder`、`enabled`、`enabledExplore`、`header`、`loginUrl`、`searchUrl`、`exploreUrl`、`variable`、`concurrentRate`、`bookUrlPattern`、`lastUpdateTime`、`respondTime`、`weight` 及 `ruleSearch`/`ruleExplore`/`ruleBookInfo`/`ruleToc`/`ruleContent`。

**规则级字段**：搜索 `bookList/name/author/kind/lastChapter/intro/coverUrl/bookUrl/wordCount`；发现 `bookList/name/author/kind/intro/coverUrl/bookUrl`；详情 `init/name/author/kind/intro/coverUrl/tocUrl/wordCount/lastChapter`；目录 `chapterList/chapterName/chapterUrl`；正文 `content/nextContentUrl`。

**规则语法**：默认正则 + `##` 替换；`@json:`（JSONPath 常用子集）、`@css:`、`@XPath:`、`@js:`（JavaScriptCore）；修饰符 `||` 回退、`-` 反转、`&&` 组合；`{{ }}` 模板（JS 与内置变量）；`@get:`/`@put:` 变量存取。

**导入/导出**：标准 Legado JSON 数组，字段原样保留，可与墨悦/阅读互通。

## 7. 工程与构建方案

- 工程用 **XcodeGen**（`project.yml`）生成：单 App target、SwiftUI 生命周期、`GENERATE_INFOPLIST_FILE` + 项目内 `Info.plist`（URL Types 支持 `shuyue://` 导入）、`TARGETED_DEVICE_FAMILY = 1,2`。生成后的 `.xcodeproj` 可被标准 Xcode 打开与 `xcodebuild` 构建。
- **GitHub Actions**（`build.yml`，macos-15）：选 Xcode → `brew install xcodegen` → `xcodegen generate` → `xcodebuild -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO` → 打包 `Payload/ShuYue.app` 为 `ShuYue-<version>.ipa` → 上传 artifact；打 `v*` tag 时创建 Release 并附带 IPA。

## 8. 里程碑

1. 规格定稿（本文件）
2. 新建公开仓库
3. 工程骨架 + 设计系统 + CI（空壳可构建）
4. Legado 书源引擎
5. 核心功能（书源/书架/搜索/阅读器）
6. 原创化视觉与信息架构核验
7. 云构建修复至成功
8. README/许可/Release 与交付