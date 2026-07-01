## MacTortoiseSVN v1.0.1

受 TortoiseSVN 启发的原生 macOS SVN 客户端。

### 本版本更新

- **修复启动崩溃** — 修复分发版 `.app` 在其他 Mac 上启动时因 `Bundle.module` 找不到资源包而崩溃的问题
- **修复状态刷新失败** — 工作台优先使用进程内状态服务，避免 XPC 辅助进程通信失败导致无法识别修改
- **修复 UTF-8 编码问题** — 修复沙盒内 `svn diff/status` 在中文路径或 UTF-8 内容下报 `E000022` / `E155007` 的问题
- **差异预览性能优化** — 增加 diff 缓存、防抖、大文件截断，并直接调用 `svn` 可执行文件以减少启动开销
- **构建改进** — 默认使用 Release 构建，提升分发包稳定性

### 功能特性

- **独立工作台** — 原生 SwiftUI macOS 客户端，支持提交、更新、日志、仓库浏览、Diff
- **访达文件状态标识** — Finder 中显示 SVN 状态图标（已修改 / 已添加 / 冲突 / 未版本控制）
- **访达右键菜单** — 右键执行 Commit / Add / Diff / Refresh
- **状态服务** — SQLite 缓存 + FSEvents 增量刷新，不阻塞 Finder
- **Rust 后端** — mtsvn-rs 命令桥，安全的 svn 命令调用
- **本地化** — 中文 / 英文界面

### 安装

1. 下载 `MacTortoiseSVN.zip`，解压后拖入 `/Applications`
2. 首次打开需授权文件访问权限（ad-hoc 签名包请右键 → 打开）
3. Finder 扩展在 **系统设置 > 隐私与安全性 > 扩展** 中启用

> 需要 macOS 14+（Apple Silicon）且已安装 Xcode Command Line Tools（提供 svn）
