#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ShuYue 六模块视图静态自检：括号平衡 / 繁体字形 / API 引用 / @MainActor 标注。"""
import re
import sys
from pathlib import Path

ROOT = Path("/home/work/dumate/e77eb6abf83440e5acc6c0318237bad4/workspace/ses_gffe5edb7c9cfaffeO6gn5olWOKD8zX/shuyue")

CHECK_FILES = [
    "App/SYAppState.swift",
    "App/SYRoute.swift",
    "App/SYRootShell.swift",
    "Design/SYComponents/SYFeedback.swift",
    "Design/SYComponents/SYBookRow.swift",
    "Features/Bookshelf/BookshelfView.swift",
    "Features/BookSource/BookSourceListView.swift",
    "Features/Search/SearchView.swift",
    "Features/Discover/DiscoverView.swift",
    "Features/History/HistoryView.swift",
    "Features/Settings/SettingsView.swift",
    "Features/BookDetail/BookDetailView.swift",
    "Features/Reader/ReaderView.swift",
]

def strip_code(src: str) -> str:
    """移除 // 注释、/* */ 注释与字符串字面量，保留结构字符。"""
    out = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        if c == '"':
            out.append('"')
            i += 1
            while i < n:
                if src[i] == "\\":
                    i += 2
                    continue
                if src[i] == '"':
                    out.append('"')
                    i += 1
                    break
                out.append(' ')
                i += 1
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            i += 2
            while i + 1 < n and not (src[i] == "*" and src[i + 1] == "/"):
                i += 1
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)

def strip_comments(src: str) -> str:
    """仅移除 // 与 /* */ 注释，保留字符串与代码，用于繁体字形检查。"""
    out = []
    i = 0
    n = len(src)
    while i < n:
        if src[i] == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                i += 1
            out.append("\n")
            continue
        if src[i] == "/" and i + 1 < n and src[i + 1] == "*":
            i += 2
            while i + 1 < n and not (src[i] == "*" and src[i + 1] == "/"):
                i += 1
            i += 2
            out.append(" ")
            continue
        out.append(src[i])
        i += 1
    return "".join(out)

def check_balance(path: Path):
    src = strip_code(path.read_text(encoding="utf-8"))
    stack = []
    pairs = {")": "(", "]": "[", "}": "{"}
    errors = []
    for idx, ch in enumerate(src):
        if ch in "([{":
            stack.append((ch, idx))
        elif ch in ")]}":
            if not stack or stack[-1][0] != pairs[ch]:
                errors.append(f"unbalanced {ch!r} at char {idx}")
                return errors
            stack.pop()
    if stack:
        errors.append(f"unclosed {[s[0] for s in stack]}")
    return errors

# 仅含简体规范字中绝不使用的繁体专有字形（繁简同形字、简体正常用字一律不放进集合）。
TRAD = set("閱讀體書這與為們說時還經過來個點進遠邊間問開關門見長雲電發覺學國裏後動頭愛歡樂聲銀銅鐵馬鳥魚龍風無沒麼許陽麗蘭雙對難離舊親憂煩節紙質驗證導覽歷設處繼續實現結構戶檔資頻寬啟閉錄紀簡規則匯網絡鏈刪確認敗錯誤內複製貼顯隱頁標題選項釋義譯護讓議論據總額鑑權責備餘數換")

# 本轮视图用到的 API / 组件 / 模型符号，检查是否在工程中出现定义。
REQUIRED_SYMBOLS = [
    # AppState api
    "func present", "func open", "func toggleDrawer",
    "var sources", "var shelf", "var history", "var settings",
    "var enabledSources", "var exploreSources", "var enabledSearchCount",
    "func source(url:", "func importSources(text:", "func importSources(remote",
    "func toggleSource", "func deleteSource", "func removeAllSources",
    "func exportSourcesText", "func validate",
    "func search(keyword:", "func exploreCategories", "func explore(source",
    "func detail(for", "func chapters(for", "func content(for",
    "func isOnShelf", "func shelfItem", "func addToShelf", "func removeFromShelf",
    "func setGroup", "func updateProgress", "func clearHistory",
    "func setTheme", "func setFontSize", "func setLineSpacing", "func setUseSerif",
    # 组件
    "struct SYScreen", "struct SYTopBar", "struct SYCapsuleTabs", "struct SYEmptyState",
    "struct SYSpineCard", "struct SYRowCard", "struct SYPillToggle", "struct SYSectionHeader",
    "struct SYBookRow", "struct SYCoverView", "struct SYProgressRing", "struct SYCard",
    "struct SYButton", "struct SYChip",
    "enum SYPalette", "enum SYMetric", "enum SYFont", "enum ReaderTheme",
    # 模型
    "struct SYBookshelfItem", "struct SYHistoryEntry", "struct SYSearchGroup",
    "struct SYExploreCategory", "struct SYImportSummary", "struct SYReaderSettings",
    "struct SYBook", "struct SYBookSource", "struct SYChapter",
]

def main():
    ok = True

    for rel in CHECK_FILES:
        p = ROOT / rel
        if not p.exists():
            print(f"[MISS] {rel}: file not found")
            ok = False
            continue

        errs = check_balance(p)
        if errs:
            print(f"[BALANCE-ERR] {rel}: {errs}")
            ok = False
        else:
            print(f"[OK] {rel}: balance")

        # 繁体字形检查：去注释后检查字符串与代码；「閱讀」为刻意引用的上游应用名，放行。
        text = p.read_text(encoding="utf-8")
        code_text = strip_comments(text).replace("閱讀", "")
        found = sorted({ch for ch in code_text if ch in TRAD})
        if found:
            print(f"[TRAD-ERR] {rel}: {found}")
            ok = False

    # 符号定义收集：收集全部非空、非注释行（放开 @Published / private(set) 等前缀修饰符）。
    defs = []
    for p in (ROOT / "App", ROOT / "Design", ROOT / "Features", ROOT / "Engine"):
        for f in p.rglob("*.swift"):
            for line in f.read_text(encoding="utf-8").splitlines():
                s = line.strip()
                if not s or s.startswith("//") or s.startswith("*"):
                    continue
                defs.append(s)
    defs_blob = "\n".join(defs)

    missing = []
    for sym in REQUIRED_SYMBOLS:
        if sym.startswith("func "):
            sig = sym[len("func "):]
            if re.search(r"func\s+" + re.escape(sig.split("(")[0]) + r"\s*\(", defs_blob) is None:
                missing.append(sym)
        elif sym.startswith("struct "):
            if re.search(r"struct\s+" + re.escape(sym[len("struct "):]) + r"\b", defs_blob) is None:
                missing.append(sym)
        elif sym.startswith("enum "):
            if re.search(r"enum\s+" + re.escape(sym[len("enum "):]) + r"\b", defs_blob) is None:
                missing.append(sym)
        elif sym.startswith("var "):
            if re.search(r"var\s+" + re.escape(sym[len("var "):]) + r"\b", defs_blob) is None:
                missing.append(sym)
        else:
            if re.search(re.escape(sym), defs_blob) is None:
                missing.append(sym)
    if missing:
        print("[SYMBOL-MISS]", missing)
        ok = False

    # @MainActor 标注检查：六个主视图与 ImportSourceSheet / DiscoverSourceSectionView。
    main_views = {
        "Features/Bookshelf/BookshelfView.swift": ["struct BookshelfView"],
        "Features/BookSource/BookSourceListView.swift": ["struct BookSourceListView", "struct ImportSourceSheet"],
        "Features/Search/SearchView.swift": ["struct SearchView"],
        "Features/Discover/DiscoverView.swift": ["struct DiscoverView", "struct DiscoverSourceSectionView"],
        "Features/History/HistoryView.swift": ["struct HistoryView"],
        "Features/Settings/SettingsView.swift": ["struct SettingsView"],
    }
    for rel, targets in main_views.items():
        text = (ROOT / rel).read_text(encoding="utf-8")
        for t in targets:
            name = t.split(" ")[-1]
            m = re.search(
                r"^@MainActor\s*\n(?:private\s+|fileprivate\s+|internal\s+|public\s+)?struct\s+"
                + re.escape(name) + r"\b",
                text, re.M,
            )
            if m is None:
                print(f"[MAINACTOR-ERR] {rel}: {t} missing @MainActor")
                ok = False
        if "PreviewProvider" in text or "_Previews" in text:
            print(f"[PREVIEW-ERR] {rel}: preview 残留")
            ok = False

    print("\nRESULT:", "PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()