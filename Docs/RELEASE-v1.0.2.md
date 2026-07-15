## MacTortoiseSVN v1.0.2

受 TortoiseSVN 启发的原生 macOS SVN 客户端。

### 本版本更新

- **修复反复权限弹窗** — 主应用与 XPC 服务启用 App Sandbox，避免访问 App Group 时反复弹出「想访问其他 App 的数据」
- **修复沙盒下无法调用 Homebrew svn** — 放行 `/opt/homebrew` 依赖库路径，避免 `libserf` 被沙盒拦截
- **修复 SVN 认证失败** — 沙盒应用无法读取钥匙串凭据时，提供应用内登录，并将账号密码用于后续更新
- **修复更新卡住转圈** — 更新操作增加超时与「取消更新」按钮，切换工作空间会自动取消卡住的任务
- **构建改进** — Helper 工具使用 inherit 签名；安装脚本不再重复签名，减少 TCC 重置

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
3. 首次更新远程仓库时，按提示输入 SVN 用户名和密码（只需一次）
4. Finder 扩展在 **系统设置 > 隐私与安全性 > 扩展** 中启用

> 需要 macOS 14+（Apple Silicon）且已安装 Subversion（推荐 Homebrew：`brew install subversion`）
