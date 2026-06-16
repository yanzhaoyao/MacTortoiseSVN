# MacTortoiseSVN 全面安全与质量审计报告

> 审计日期：2026-06-15  
> 范围：MacTortoiseSVN 全代码库（Swift 6.0 主应用 + FinderSync 扩展 + XPC 状态服务 + Rust 命令桥）  
> 审计员：Hermes Agent

---

## 总览

| 严重程度 | 数量 | 关键主题 |
|----------|------|----------|
| 🔴 严重/高危 | 6 | DistributedNotification 欺骗、SQLite 句柄泄漏、路径穿越、沙盒缺失 |
| 🟡 中危 | 14 | 并发竞态、Sendable 不安全标注、输入校验缺失、debug entitlement |
| 🟢 低危 | 16 | DoS 向量、日志信息泄漏、构建脚本问题 |
| ✅ 正面发现 | 8 | 零 shell 注入、零 SQL 注入、零 unsafe Rust、零外部依赖 |
| **合计** | **36** | |

---

## 🔴 严重/高危 (6 项)

### C1. DistributedNotification 可被任意进程欺骗和窃听
**位置**: `FinderSyncBridge.swift:148,250`, `WorkbenchModel.swift:298-308`, `MacSVNFinderSyncExtension.swift:93,101`  
**影响**: 任意本地进程可以：
- **窃听** `userInfo` 字典中的监控根路径和工作台命令
- **伪造** 通知，注入任意路径或命令
- **触发** 强制工作台广播其监控根目录

通知名称是可发现的（嵌入二进制的反向 DNS 字符串），无发送者验证或消息认证。

**建议**: 迁移至 `NSXPCConnection` 做进程间通信。

### C2. sqlite3_open_v2 失败时泄漏数据库句柄
**位置**: `SQLiteStatusCacheStore.swift:270-280`  
**影响**: SQLite 文档明确指出，即使 `sqlite3_open_v2` 返回错误，仍会分配一个有效的 `sqlite3*` 句柄，必须用 `sqlite3_close()` 关闭。当前错误路径直接 throw，泄漏句柄和文件描述符。

**修复**: 在 guard 之前添加 `defer { if result != SQLITE_OK { sqlite3_close(database) } }`

### C3. 主应用和 XPC 服务缺少沙盒
**位置**:  
- `MacSVNWorkbench.entitlements` — `com.apple.security.app-sandbox` **缺失**
- `MacSVNStatusService.entitlements` — `com.apple.security.app-sandbox` **缺失**  
**影响**: 主应用和 XPC 服务均以非沙盒模式运行，拥有不受限的文件系统访问权限。仅 FinderSync 扩展启用了沙盒。

**建议**: 如非必要（SVN 客户端确实需要访问任意工作副本），应记录为有意设计决策。

### C4. Force Unwrap 崩溃风险
**位置**: `WorkbenchModel.swift:1382`  
```swift
panel.allowedContentTypes = [.init(filenameExtension: "patch")!]
```
**影响**: 若系统未注册 "patch" UTI，`UTType(filenameExtension:)` 返回 nil 时将崩溃。

**修复**: 使用 `?? .data` 降级。

### C5. 重命名操作未校验路径穿越
**位置**: `WorkbenchModel.swift:1350-1355`  
**影响**: 用户输入 `../../etc/cron.d/malicious` 时，`NSString.appendingPathComponent` 会解析到工作副本外的路径。虽 SVN 自身会拒绝，但缺少应用层校验。

### C6. svn:externals 属性注入风险
**位置**: `WorkbenchModel.swift:1437-1457`  
**影响**: `propset` 的 `name` 和 `value` 来自用户输入，未校验。设置 `svn:externals` 恶意值可导致 SVN 从攻击者控制的仓库拉取外部内容。

---

## 🟡 中危 (14 项)

### M1. SQLiteConnection 标记 @unchecked Sendable 但无同步保护
**位置**: `SQLiteStatusCacheStore.swift:438`  
**说明**: `OpaquePointer` 不满足 Sendable，`@unchecked` 抑制编译器检查。虽当前仅在 actor 内使用，但类本身无保护。

### M2. FSEventStreamState 标记 @unchecked Sendable
**位置**: `FSEventsWorkingCopyWatcher.swift:157`  
**说明**: `FSEventStreamRef` 是 CFType，`@unchecked` 标注存在代码气味。

### M3. FSEvents 回调中的非结构化 Task 可能超出 Watcher 生命周期
**位置**: `FSEventsWorkingCopyWatcher.swift:37-44`  
**说明**: `Task` 块创建的非结构化异步工作可在 `stopMonitoring()` 后继续执行，持有 `self` 强引用延长 actor 生命周期。

### M4. 事务回滚错误被静默吞没
**位置**: `SQLiteStatusCacheStore.swift:420`  
**说明**: `try? execute("ROLLBACK")` 若失败（数据库损坏、磁盘满），错误被丢弃，可能导致后续操作 "database is locked"。

### M5. 错误消息泄漏 SQL 语句
**位置**: `SQLiteStatusCacheStore.swift:309,324,345,359`  
**说明**: 完整 SQL 语句包含在错误消息中，暴露内部 schema 结构。

### M6. 路径输入缺少验证
**位置**: `SubversionWorkspaceOperator.swift`（所有方法）, `SubversionRepositoryInspector.swift`, `RustCommandBridgeSVNClient.swift`  
**说明**: 所有公共方法接受原始 `String` 路径，无绝对路径检查、无 `..` 穿越检查、无空字节检查。

### M7. 使用 /usr/bin/env 解析 svn — PATH 依赖
**位置**: `SubversionRepositoryInspector.swift:273`, `RustCommandBridgeSVNClient.swift:91,145`  
**说明**: 实际解析的 `svn` 二进制依赖 PATH 环境变量，`macSVNExtendedExecutablePath` 添加的目录若被写入恶意二进制，存在 binary planting 风险。

### M8. MacSVNSecurityScopedAccess 竞态条件
**位置**: `SecurityScopedBookmarks.swift:3-27`  
**说明**: `isActive` 标记 `@unchecked Sendable` 但读写无任何锁保护，`stop()` 可在 `deinit`（任意线程）调用。

### M9. 外部工具启动路径未校验
**位置**: `ExternalToolLauncher.swift:69`, `PlatformIntegration.swift:94-115`  
**说明**: `ExternalToolProfile.launchPath` 直接用作 `executableURL`。自定义配置文件若被篡改可启动任意可执行文件。

### M10. FinderSync 信号量阻塞线程
**位置**: `MacSVNFinderSyncExtension.swift:375-404`  
**说明**: `DispatchSemaphore.wait` 在 FinderSync 扩展中阻塞线程，大量并发菜单请求可能导致线程池耗尽。

### M11. 日志文件权限过于宽松
**位置**: `WorkbenchModel.swift:3464-3488`, `MacSVNFinderSyncExtension.swift:546-571`  
**说明**: 诊断日志写入 `~/Library/Application Support/MacTortoiseSVN/` 和 FinderSync 日志，使用默认权限，系统上其他用户可读。

### M12. debug entitlement 残留于所有构建
**位置**: 所有三个 entitlements 文件  
**说明**: `com.apple.security.get-task-allow` = true，允许调试器附加。构建脚本未在 release 构建中剥离此项。

### M13. Rust 自定义 XML 解析器脆弱性
**位置**: `svn_backend/src/lib.rs:356-407`  
**说明**: 手写 XML 解析使用字符串切分，`>` 匹配可能在属性值中错误命中；`decode_xml_entities` 仅处理 5 个标准实体，数字字符引用（`&#NNN;`）被静默跳过。

### M14. XMLParser 未防护 XML Bomb
**位置**: `SubversionRepositoryInspector.swift:491,506,522,536`  
**说明**: `Foundation.XMLParser` 无内置 XML bomb 防护。恶意 SVN 仓库可提供指数级实体扩展的 XML。

---

## 🟢 低危 (16 项)

| # | 问题 | 位置 |
|---|------|------|
| L1 | commit message 无长度限制，可能触发 ARG_MAX | `RustCommandBridgeSVNClient.swift:321` |
| L2 | `accept` 参数用原始 String 而非 enum | `SubversionWorkspaceOperator.swift:156,225` |
| L3 | StatusServiceHost.handle(event:) 静默吞没所有错误 | `StatusServiceHost.swift:212-214` |
| L4 | schemaSQL 通过 sqlite3_exec 执行（多语句模式） | `SQLiteStatusCacheStore.swift:294,365-380` |
| L5 | commitMessage 未过滤控制字符 | `WorkbenchModel.swift:2310-2338` |
| L6 | 多个 Task 块缺少取消传播检查 | `WorkbenchModel.swift:943-987` |
| L7 | 临时目录使用默认权限 | `WorkbenchModel.swift:293-295` |
| L8 | Bookmark 数据存储在共享 UserDefaults | `SecurityScopedBookmarks.swift:127-133` |
| L9 | lastMenuSelectionContext 可能过期 | `MacSVNFinderSyncExtension.swift:89,151,222` |
| L10 | rootPath 从命令行参数直接接受 | `WorkbenchModel.swift:271-274` |
| L11 | 仓库浏览器 URL 无路径包含检查 | `WorkbenchModel.swift:2670-2713` |
| L12 | Rust escape_json() 未处理 U+0000–U+001F 控制字符 | `main.rs:281-288` |
| L13 | MACSVN_SVN_BINARY 环境变量可指向任意二进制 | `svn_backend/src/lib.rs:459` |
| L14 | 构建脚本硬编码 /opt/homebrew/bin/cargo | `build_workbench_app.sh:84` |
| L15 | install 脚本 pkill -f 使用 glob 模式 | `install_workbench_app.sh:54-55` |
| L16 | FinderSync 扩展冗余签名 | `build_workbench_app.sh:137-142` |

---

## ✅ 正面发现 (8 项)

| # | 发现 | 说明 |
|---|------|------|
| P1 | **零 Shell 注入** | 所有子进程均经 `Process` + `arguments` 数组调用，不经过 shell |
| P2 | **零 SQL 注入** | `SQLiteStatusCacheStore` 全程 `sqlite3_bind_*` 参数化绑定 |
| P3 | **`--` 选项终止符** | 所有 svn CLI 调用正确使用 `--` 防止选项注入 |
| P4 | **零 unsafe Rust** | 三个 Rust crate 无任何 `unsafe` 块或原始指针使用 |
| **P5** | **零外部 Rust 依赖** | 所有 crate 仅使用内部路径引用，零 supply chain 攻击面 |
| P6 | **Swift Actor 隔离** | 所有核心组件正确使用 Swift actor 进行并发安全 |
| P7 | **无硬编码凭证** | 未发现任何 API key、密码、token |
| P8 | **XMLParser 使用** | 仓库检查器使用 `XMLParser`（默认禁用外部实体，无 XXE） |

---

## Rust 测试覆盖缺口

| 缺失测试 | 位置 |
|----------|------|
| `StatusRequest::parse()` | `main.rs:89-129` |
| `PathsRequest::parse()` | `main.rs:139-176` |
| `CommitRequest::parse()` | `main.rs:185-216` |
| `escape_json()` | `main.rs:281-288` |
| JSON 输出序列化 | `main.rs:219-278` |
| XML 实体边界用例 | `svn_backend/src/lib.rs:448-455` |
| 命令失败错误路径 | `svn_backend/src/lib.rs:320-332` |
| 畸形 XML 解析负测试 | `svn_backend/src/lib.rs:356-407` |

---

## 🎯 优先修复建议（按紧急程度排序）

1. **修复 sqlite3_open_v2 句柄泄漏** — 一行 defer 修复，零风险
2. **为重命名/propset 添加输入校验** — 路径穿越 + 属性名白名单
3. **迁移 DistributedNotification → NSXPCConnection** — 消除本地进程欺骗/窃听
4. **剥离 release 构建的 get-task-allow** — 安全发布前提
5. **日志文件设置 0o600 权限** — 防止信息泄漏
6. **为 Rust CLI 解析和 escape_json 补充测试** — 覆盖已知缺陷
7. **记录"无沙盒"为有意设计决策** — 在 SECURITY_AUDIT.md 中说明

---

## 与上一轮审计对比

上一轮审计（2026-06-13）已修复：
- ✅ svn `--` 选项终止符 — 已全面部署
- ✅ svn log 解析改用 XMLParser — 已修复

本轮新发现主要集中在：进程间通信安全、SQLite 资源管理、并发正确性、沙盒策略、测试覆盖。
