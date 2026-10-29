# Changelog
## 4.4.2 Build 266 (2026-10-29)
### 新增
- 完整接入「继续注入」：`InjectorV3.injectContinuing(_:shouldPersist:)` 改为逐插件事务式注入，单个插件失败只回滚它自己，其余插件继续。
- 注入结果页列出失败插件清单（`InjectOutcome.failureDetails`）。
- 失败页不再显示「Continue Inject」按钮（与「查看日志」重复），只保留「查看日志」；「继续注入」功能本身仍默认可用（由注入流程 / 列表页入口驱动），未被禁用。
- 新增 `AppSymbol` 图标集中管理（`Constants.swift`）：启动图标 `arrow.triangle.2.circlepath.circle`、继续注入图标 `arrow.triangle.2.circlepath`。
### 修复
- `FailureView` 的重试按钮样式加 iOS 15 可用性判断（iOS 14 回退 `BorderlessButtonStyle`），修复 `'borderedProminent' is only available in iOS 15.0 or newer` 归档失败。
- 注入目标选择：插件固定到「主程序」时回落到 259 风格的自动选择逻辑，不再强制返回 App 主二进制。
------
## 4.4.2 Build 266 (2026-10-29) [EN]
### Added
- Full "Continue Injection": `InjectorV3.injectContinuing(_:shouldPersist:)` injects plug-ins one by one transactionally, so a single failure only rolls back itself while the rest continue.
- The injection result screen lists the failed plug-ins (`InjectOutcome.failureDetails`).
- The failure screen no longer shows the extra "Continue Inject" button (it duplicated "View Logs"); only "View Logs" remains. "Continue Injection" itself stays enabled by default (driven by the injection flow / list-page entry) and is not disabled.
- Added centralized `AppSymbol` SF Symbol definitions (`Constants.swift`): launch `arrow.triangle.2.circlepath.circle`, continue-injection `arrow.triangle.2.circlepath`.
### Fixed
- `FailureView`'s retry button style is now guarded by an iOS 15 availability check (falls back to `BorderlessButtonStyle` on iOS 14), fixing the archive failure `'borderedProminent' is only available in iOS 15.0 or newer`.
- Injection target selection: when a plug-in is pinned to the main executable, fall back to the legacy (259-style) automatic selection instead of force-returning the app binary.
------
## 4.4.2 Build 265 (2026-10-29)
### 新增
- 注入失败页支持多行失败清单（`details`）与重试按钮（`retryTitle` / `onRetry`），可在结果页直接执行「继续注入」，只重试失败的插件。
### 修复
- `FailureView` 的重试按钮样式改用 iOS 15 可用性判断（iOS 14 回退 `BorderlessButtonStyle`），修复归档失败：`'borderedProminent' is only available in iOS 15.0 or newer`。
- `AppListCell` 的 Launch 菜单图标恢复为字面量 `command`，移除对未定义 `AppSymbol` 类型的引用。
------
## 4.4.2 Build 265 (2026-10-29) [EN]
### Added
- The inject failure screen now supports a multi-line failure list (`details`) plus a retry button (`retryTitle` / `onRetry`), letting you run "Continue Injection" right on the result screen and retry only the failed plug-ins.
### Fixed
- `FailureView`'s retry button style is now guarded by an iOS 15 availability check (falls back to `BorderlessButtonStyle` on iOS 14), fixing the archive failure: `'borderedProminent' is only available in iOS 15.0 or newer`.
- `AppListCell`'s Launch menu icon is back to the literal `command`, removing the reference to the undefined `AppSymbol` type.
------
## 4.4.2 Build 263 (2026-10-24)

### 修复
- 应用列表的 `fetchApplications` 枚举移到后台队列执行，结果回主线程一次性刷新，避免后台时触发 `scene-update` watchdog（主线程饱和）。

------
## 4.4.2 Build 263 (2026-10-24) [EN]

### Fixed
- `fetchApplications` now runs off the main thread and refreshes once on the main queue, preventing a `scene-update` watchdog when the app goes to the background.

------

## 4.4.2 Build 262 (2026-10-22)

### 修复
- 插件列表的注入目标列表改为后台异步扫描并缓存，避免在 SwiftUI `body` 里反复解析 Mach-O，修复主线程卡死与被 watchdog 终止（`0x8badf00d`）。
- 注入 / 卸载 / 切换注入目标的耗时操作统一移到后台队列（`runInBackground`）执行，完成后自动刷新列表，界面不再假死。

------
## 4.4.2 Build 262 (2026-10-22) [EN]

### Fixed
- Injection-target scanning now runs asynchronously on a background queue and is cached, no more Mach-O re-parsing inside SwiftUI `body` (which froze the main thread and triggered a watchdog termination, `0x8badf00d`).
- Inject / eject / retarget work is executed off the main thread via `runInBackground`, and the list refreshes when it finishes.

------

## 4.3 Build 253 (2026-04-23)

修复与 MachOKit 有关的一处断言崩溃。

------

## 4.3 Build 253 (2026-04-23) [EN]

Fixed an assertion crash related to MachOKit.

------

## 4.3 Build 246 (2026-04-16)

修复二次注入时可能误选已注入动态库作为目标 Mach-O 的问题。

### 修复

- 注入目标选取：修复追加注入时，上次注入的动态库可能被误选为注入目标的问题。  
  新增三层防御：从注入前备份读取原始 Load Commands 以还原真实依赖链；枚举阶段跳过 `.troll-fools.bak` 备份文件；通过备份差分精确识别并排除已注入的动态库。

------

## 4.3 Build 246 (2026-04-16) [EN]

Fixed an issue where re-injection could incorrectly select a previously-injected dylib as the target Mach-O.

### Fixed

- Target selection: Fixed re-injection potentially picking a previously-injected dylib as the injection target.  
  Added three-layer defense: read original load commands from pre-injection backup to restore the true dependency chain; skip `.troll-fools.bak` backup files during enumeration; use backup-diff to precisely identify and exclude previously-injected dylibs.

------

## 4.3 (2026-04-13)

本次版本聚焦于“动态加载框架兼容性”和“页面说明可理解性”，并包含插件管理流程调整与资源清理。

### 修复

- 注入兼容性：修复部分 Unity/运行时 `dlopen` 场景下无法命中可注入目标的问题。  
  当主程序静态链接交集为空时，改为回退扫描 `Frameworks/` 中可用 Mach-O（含一级目录下 `.dylib`）。
- 插件管理：调整“移除插件”流程，区分已启用与已禁用插件：  
  已启用插件执行卸载；已禁用插件执行标记清理，降低批量处理风险。

### 新增

- 高级选项：新增“启用兼容模式回退”开关（默认开启），可控制是否在无静态链接命中时启用回退候选。
- 结果页提示：当本次注入通过兼容模式完成时，在“已完成”下方显示额外提示。

### 优化

- 候选筛选：回退候选新增过滤，排除 `libswift*` 与已忽略注入相关动态库/框架，并统一大小写处理。
- 诊断日志：增强 Mach-O 扫描日志，输出候选数量、文件大小、加密/不可读统计与最终选择结果，便于定位“无可用目标”问题。
- 设置说明：优化高级选项页面结构与说明文案，减少非技术用户理解成本。
- 广告与资源：移除内置广告位 `Letterpress` 及相关本地化词条/图标资源；更新营销图素材。

### 本地化

- 更新 `en/zh-Hans/it/vi` 词条，补充兼容模式与设置说明相关文案，并清理移除条目对应文案。

------

## 4.3 (2026-04-13) [EN]

This release focuses on dynamic-framework injection compatibility and clearer user guidance, plus plugin-management flow adjustments and resource cleanup.

### Fixed

- Injection compatibility: Fixed cases (notably Unity/runtime `dlopen` flows) where no injectable target could be selected.  
  When the static-link intersection is empty, TrollFools now falls back to scanning eligible Mach-O files under `Frameworks/` (including top-level `.dylib`).
- Plugin management: Updated plugin removal flow to handle enabled vs disabled plugins separately:  
  enabled plugins are ejected, while disabled plugins are cleaned via desist/marker path handling.

### Added

- Advanced Settings: Added **Enable Compatibility Fallback** (default ON) to control fallback candidate behavior when no static-link match is found.
- Result-page notice: Added a subtitle under **Completed** when injection succeeds through compatibility fallback.

### Improved

- Candidate filtering: Fallback candidates now exclude `libswift*` and ignored injection-related dylib/framework names, with consistent case-insensitive handling.
- Diagnostics: Expanded Mach-O scan logs with candidate counts, file sizes, encrypted/unreadable stats, and final target selection.
- Settings clarity: Refined Advanced Settings layout and explanatory copy for better non-technical readability.
- Ads/assets: Removed built-in `Letterpress` ad entry and related localization/icon assets; refreshed marketing artwork.

### Localization

- Updated `en/zh-Hans/it/vi` strings for compatibility-fallback and settings guidance, and removed strings for deleted entries.
