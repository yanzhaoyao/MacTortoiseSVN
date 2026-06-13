# 安全审计报告 / Security Audit

> 审计日期：2026-06-13 · 范围：MacTortoiseSVN（Swift/SwiftUI 主应用 + FinderSync 扩展 + XPC 状态服务 + Rust 命令桥）

本文记录一轮针对进程间通信、子进程调用与数据持久化的安全审计结论，以及随之落地的加固改动。

## 概览

| 区域 | 结论 |
| --- | --- |
| Shell 命令注入 | ✅ 无。所有子进程均经 `Process` + `arguments` 数组调用，不经过 shell |
| SQL 注入 | ✅ 无。`SQLiteStatusCacheStore` 全程 `sqlite3_bind_*` 参数化绑定 |
| XPC 信任边界 | ⚠️ 当前为宿主 App 内嵌 XPC service，尚未实现 client audit / code signing requirement 校验；FinderSync 当前不依赖它取状态 |
| 扩展 ↔ 主应用数据通路 | ✅ 走 App Group 共享容器 + `DistributedNotification`，未假设 XPC 可达 |
| XML 解析 | ✅ 仓库检查器使用 `XMLParser`（默认禁用外部实体，无 XXE） |
| **svn 选项注入** | ⚠️ **已修复**。位置参数缺少 `--` 终止符（见下） |
| svn 日志解析健壮性 | ⚠️ **已修复**。手写字符串解析替换为 `XMLParser` |

## 发现与修复

### 1. svn 调用缺少 `--` 选项终止符（option injection）— 已修复

**等级**：中低危（本地、需特制输入）

**描述**：所有 `svn` 子命令此前把路径 / URL / 名称等操作数直接拼接在选项之后，且未使用 `--` 终止选项解析。若某个操作数以 `-` 开头，`svn` 会将其当作**选项**解释。`svn diff` 等子命令支持 `--diff-cmd=PROG`、`--config-dir=DIR` 等，理论上可被滥用以影响外部命令调用或配置加载。

**可达性**：
- 来自 Finder/列表选择的操作数为**绝对路径**（以 `/` 开头），天然不会被当作选项，风险有限。
- 真正暴露面是**用户/服务端可控的非路径输入**：shelve / unshelve 的名称、用户粘贴的仓库 URL、`svn:propset` 的属性名与属性值等。属于自害或恶意工作副本场景。

**修复**：在每个 svn 调用的位置参数前插入 `--`，并把原先位于操作数之后的选项前移，确保 `--` 之后仅剩纯操作数。涉及文件：

- `Sources/SVNCore/SubversionDiffInspector.swift`
- `Sources/SVNCore/SubversionWorkspaceOperator.swift`
- `Sources/SVNCore/SubversionRepositoryInspector.swift`
- `Sources/SVNCore/RustCommandBridgeSVNClient.swift`（shelve / unshelve / log）
- `Sources/MacSVNWorkbench/WorkbenchModel.swift`（delete / propget / propset / propdel / blame / lock / unlock / move / diff / proplist）

**示例**：

```diff
- arguments: ["update", rootPath, "--depth", depth, "--accept", accept]
+ arguments: ["update", "--depth", depth, "--accept", accept, "--", rootPath]

- arguments: ["diff", path]
+ arguments: ["diff", "--", path]

- arguments: ["propset", name, value, path]
+ arguments: ["propset", "--", name, value, path]
```

> 说明：经由 Rust 命令桥的 add / commit 走的是 `--path <p>` 具名参数，本身不受影响，未改动。

### 2. svn log 解析改用 XMLParser — 已修复

**描述**：`RustCommandBridgeSVNClient` 此前用手写字符串切分（`components(separatedBy:)` / `split(separator: "revision=")`）解析 `svn log --xml`，在提交说明含 `revision=`、`<msg>` 等字样时可能误解析。

**修复**：抽取共享函数 `parseSubversionLogXML(_:)`（位于 `SubversionRepositoryInspector.swift`，复用既有 `SubversionLogXMLParserDelegate`），`RustCommandBridgeSVNClient.log` 改为调用它；删除原手写的 `parseSVNLogOutput` / `parseSVNDate`。

## 验证

- `swift build` 通过。
- `swift test` 全部用例通过；受参数顺序断言影响的测试已同步更新：
  - `Tests/SVNCoreTests/SubversionWorkspaceOperatorTests.swift`
  - `Tests/SVNCoreTests/SubversionDiffInspectorTests.swift`
  - `Tests/SVNCoreTests/SubversionRepositoryInspectorTests.swift`
  - `Tests/SVNCoreTests/RustCommandBridgeSVNClientTests.swift`

## 后续建议

- TODO：对仓库 URL / shelf 名等用户输入增加轻量校验，与 `--` 形成纵深防御：拒绝以 `-` 开头、包含控制字符、为空或仅空白、以及超过合理长度上限的值。
- 考虑为 svn 调用统一一个封装层，集中处理 `--` 与参数顺序，避免新增调用点时再次遗漏。
