<p align="center">
  <a href="https://github.com/heyeuca/Tilde/releases"><img src="docs/assets/icon.png" alt="Tilde 图标" width="128" height="128"></a>
</p>

<h1 align="center">Tilde</h1>

<p align="center">
  <a href="https://github.com/heyeuca/Tilde/actions/workflows/ci.yml"><img src="https://github.com/heyeuca/Tilde/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
</p>

*[English](README.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · 简体中文*

**一款小巧而精致的 macOS 文本编辑器。**

> `~` —— 主目录、纯文本，别无其他，恰好够用。

---

## Tilde 是什么？

软件的构建方式已经改变。在 AI 辅助开发普及之后，你亲手阅读和修改代码的次数大大减少——所以仅仅为了看一眼某个 `.txt` 或 `.md` 文件就打开一个完整的 IDE，未免太过繁重。

Tilde 填补了这段空白。它是一款面向 macOS 的超轻量文本编辑器，只围绕一个想法而生：打开文件、阅读它、也许改动一行、然后关闭。没有项目，没有工作区，没有插件，没有终端，没有侧边栏。

目标不是做一个更小的 IDE。目标是让编辑器隐于无形，只留下内容本身。

## 核心理念

- **即时 (Instant)** —— 双击文件，几乎立即打开。
- **安静 (Quiet)** —— 界面永远不会比内容更抢眼。
- **原生 (Native)** —— 它的行为就像一款 macOS 内置应用。
- **精致 (Beautiful)** —— 阅读文本本身就是一种享受。
- **轻装 (Disposable)** —— 几乎没有什么需要配置或管理。

## 适合谁

Tilde 适合想要快速阅读或轻度编辑纯文本文件的人：

- 与 AI 协作、待在代码编辑器里的时间越来越少的开发者
- 经常阅读 Markdown 文档的人
- 想在不启动重型编辑器的情况下,快速查看 README、笔记或配置文件的人

它**不是** IDE，不是项目工作区，不是笔记数据库，也不是 Markdown 写作套件。如果你需要 Git 集成、插件或多文件导航，Tilde 有意成为那个「不合适」的工具。

## 功能

- 原生 macOS 基于文档的应用（一个文件 → 一个窗口）
- 打开、编辑并保存 `.txt`、`.md` 和 `.markdown` 文件
- 以纯文本方式打开大多数基于 UTF 的纯文本文件（`.json`、`.yaml`、`.toml`、`.xml`、`.csv`、`.log`、`.env` 等），包括 `Dockerfile` 或 SSH 密钥（`id_ed25519`、`id_ed25519.pub`）这类没有扩展名或扩展名不常见的文件
- 轻量的 Markdown 样式，在保留语法标记可见的同时提升可读性
- 阅读模式（`⌘⇧R`）—— 将 Markdown 文档完整渲染为只读视图，包含表格、高亮的代码块、任务列表复选框，以及以安静标题区呈现的 YAML front matter（`title:` 作为页首标题，其余键逐行列出）；`#fragment` 链接在文档内跳转，网页链接在浏览器中打开。指向相邻本地文件的链接和图片，会在 macOS 授予文件访问权限时正常工作—— App Sandbox 可能会拦截与文档相邻的文件（被拦截的图片显示其替代文本，被拦截的链接则无反应）。可从标题栏切换，就像 Safari 的阅读器一样
- 面向配置文件的安静语法高亮：只为 `.json`、`.yaml` 和 `.toml` 中的键着色，其余保持原样
- 标准编辑操作：撤销 / 重做、剪切 / 复制 / 粘贴、拖放、拼写检查、查找与替换
- 自动换行（默认开启）以及可选的行号显示
- 采用 macOS 语义色彩的浅色 / 深色 / 跟随系统外观
- 跟随 macOS 语言设置的英语 / 韩语 / 日语 / 简体中文界面
- 快速启动，空闲时资源占用几近于零
- 完整的 macOS 集成：打开方式、文件关联、最近打开的文稿、自动保存、版本、全屏、窗口标签页
- GitHub 与 Homebrew 版本的应用内更新：只有在你选择 **Tilde → 检查更新…** 时才会检查（App Store 版本由 App Store 负责更新）

### Markdown，点到为止

对于 Markdown 文件，Tilde 会施加克制的语义样式。标题的 `#` 依然可见，文字只是略微放大；`**加粗**` 保留其标记，同时可将其中的文本以粗体呈现。目的不是隐藏 Markdown，而是让它更易于阅读。

应用样式的元素：标题、加粗、斜体、删除线、行内代码、代码块、引用、链接、无序列表、有序列表、任务列表和水平分隔线。文档开头的 YAML front matter 以淡色原样显示，其中不应用 Markdown 样式。

## 键盘快捷键

Tilde 遵循 macOS 惯例。

| 操作 | 快捷键 |
| --- | --- |
| 新建 | `⌘N` |
| 打开 | `⌘O` |
| 保存 | `⌘S` |
| 另存为 | `⌘⇧S` |
| 关闭 | `⌘W` |
| 查找 | `⌘F` |
| 查找下一个 | `⌘G` |
| 查找上一个 | `⌘⇧G` |
| 查找与替换 | `⌥⌘F` |
| 阅读模式 | `⌘⇧R` |
| 偏好设置 | `⌘,` |
| 增大字号 | `⌘+` |
| 减小字号 | `⌘-` |
| 重置字号 | `⌘0` |

## 隐私

Tilde 在本地处理每一份文档。

- 不上传至服务器
- 无需账户或登录
- 无云存储
- 无 AI 功能
- 首个版本不含任何分析统计
- 不访问网络——仅在 GitHub 与 Homebrew 版本中由你手动选择“检查更新…”时例外

## 构建

Tilde 使用 Swift、SwiftUI 和 AppKit 构建，以 SwiftUI 为主要技术，并在需要成熟文本引擎之处封装 `NSTextView`。

环境要求：

- macOS
- Xcode

构建并运行：

```bash
open Tilde.xcodeproj
```

然后在 Xcode 中构建并运行（`⌘R`）。

这样构建的是不含更新功能的 App Store 版本配置。GitHub 与 Homebrew 版本的构建由 `scripts/build_direct.sh` 加入 Sparkle 生成，详见 [docs/RELEASING.md](docs/RELEASING.md)。

## Non-Goals（有意不做的事）

Tilde 有意舍弃一切会让它重新变回完整 IDE 的东西：

- 终端、Git、调试器、构建 / 运行、LSP、IntelliSense、重构、项目浏览器
- 扩展、插件、市场
- 笔记数据库、标签、反向链接、知识库、Wiki、同步
- 账户、评论、共享工作区、实时协作
- AI 补全、聊天、改写或智能体

关于这些决定背后完整的产品思考，请参阅 [docs/PRODUCT.md](docs/PRODUCT.md)。

## 许可证

Tilde 基于 [MIT License](LICENSE) 发布。

---

> **只管打开文件。**
