//
//  InjectorV3+Continue.swift
//  TrollFools
//
//  「继续注入」：把一次注入拆成“逐插件事务”。
//
//  `inject(_:shouldPersist:)` 是「全有或全无」的：任何一个插件抛错都会把
//  整批资源回滚。这里提供另一种语义：每个插件独立提交 / 回滚，失败的插件
//  被收集起来返回给调用方，其余插件照常注入。界面据此可以显示「继续注入」，
//  只重试失败的那一部分。
//

import CocoaLumberjackSwift
import Foundation

extension InjectorV3 {
    // MARK: - Result Model

    /// 单个插件失败的记录。
    struct InjectFailure {
        /// 失败发生的阶段。
        enum Stage: String {
            case preprocess
            case bundle
            case machO
        }

        let assetURL: URL
        /// 用户最初选择的文件（`zip` / `deb` 时为压缩包本身），用于「继续注入」重试。
        let sourceURL: URL
        let stage: Stage
        let error: Swift.Error

        var localizedDescription: String {
            "\(assetURL.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// 一次（或多次连续）注入的结果。
    struct InjectOutcome {
        /// 已成功注入的插件（预处理后的 URL）。
        var succeeded: [URL] = []
        /// 失败的插件及其原因。
        var failed: [InjectFailure] = []
        /// 是否走了兼容模式（枚举 `Frameworks/` 中的全部 Mach-O）。
        var didUseFallback = false

        var isEmpty: Bool { succeeded.isEmpty && failed.isEmpty }
        var isComplete: Bool { !succeeded.isEmpty && failed.isEmpty }
        var isPartial: Bool { !succeeded.isEmpty && !failed.isEmpty }
        var isTotalFailure: Bool { succeeded.isEmpty && !failed.isEmpty }

        var failedAssetURLs: [URL] { failed.map(\.sourceURL) }

        /// 供界面展示的多行失败清单。
        var failureDetails: String {
            failed.map { "· \($0.localizedDescription)" }.joined(separator: "\n")
        }

        /// 合并「继续注入」的结果：同名的插件以新结果为准。
        mutating func merge(_ other: InjectOutcome) {
            let retriedNames = Set(
                other.succeeded.map(\.lastPathComponent)
                    + other.failed.map(\.assetURL.lastPathComponent)
            )

            succeeded.removeAll { retriedNames.contains($0.lastPathComponent) }
            failed.removeAll { retriedNames.contains($0.assetURL.lastPathComponent) }

            succeeded += other.succeeded
            failed += other.failed
            didUseFallback = didUseFallback || other.didUseFallback
        }
    }

    // MARK: - Continue Injection

    /// 逐插件注入；某个插件失败时只回滚它自己，其余继续。
    ///
    /// - Parameters:
    ///   - assetURLs: 待注入的插件（`dylib` / `framework` / `bundle` / `zip` / `deb`）。
    ///   - shouldPersist: 是否把**成功**的插件写入持久化目录。
    @discardableResult
    func injectContinuing(_ assetURLs: [URL], shouldPersist: Bool) -> InjectOutcome {
        var outcome = InjectOutcome()
        guard !assetURLs.isEmpty else {
            return outcome
        }

        didUseMachOEnumerationFallback = false

        // 1. 预处理：逐个插件进行，坏包只影响它自己。
        var preparedURLs: [URL] = []
        /// 预处理结果 → 用户最初选择的文件。
        var sourceOf: [URL: URL] = [:]
        for assetURL in assetURLs {
            do {
                let prepared = try preprocessAssets([assetURL])
                for url in prepared {
                    sourceOf[url] = assetURL
                }
                preparedURLs += prepared
            } catch {
                DDLogError("Preprocess failed for \(assetURL.lastPathComponent): \(error)", ddlog: logger)
                outcome.failed.append(
                    InjectFailure(assetURL: assetURL, sourceURL: assetURL, stage: .preprocess, error: error)
                )
            }
        }

        guard !preparedURLs.isEmpty else {
            outcome.didUseFallback = didUseMachOEnumerationFallback
            return outcome
        }

        terminateApp()

        // 2. Bundle：逐个拷贝到 .app/ 根目录。
        for assetURL in preparedURLs where assetURL.pathExtension.lowercased() == "bundle" {
            do {
                try applyBundle(assetURL)
                outcome.succeeded.append(assetURL)
                DDLogInfo("Injected bundle \(assetURL.lastPathComponent)", ddlog: logger)
            } catch {
                DDLogError("Inject bundle failed for \(assetURL.lastPathComponent): \(error)", ddlog: logger)
                outcome.failed.append(
                    InjectFailure(assetURL: assetURL, sourceURL: sourceOf[assetURL] ?? assetURL, stage: .bundle, error: error)
                )
                try? cmdRemove(
                    bundleURL.appendingPathComponent(assetURL.lastPathComponent),
                    recursively: true
                )
            }
        }

        // 3. dylib / framework：每个插件独立提交或回滚。
        let machOAssetURLs = preparedURLs.filter {
            let ext = $0.pathExtension.lowercased()
            return ext == "dylib" || ext == "framework"
        }

        if !machOAssetURLs.isEmpty {
            let substrateFwkURL = prepareSubstrateIfNeeded()

            // 同一批次里的插件注入到同一个宿主 Mach-O（与 `inject()` 保持一致）。
            var targetMachO: URL?
            do {
                guard let machO = try locateAvailableMachO() else {
                    DDLogError("All Mach-Os are protected", ddlog: logger)
                    throw Error.generic(NSLocalizedString("No eligible framework found.\n\nIt is usually not a bug with TrollFools itself, but rather with the target app. You may re-install that from App Store. You can’t use TrollFools with apps installed via “Asspp” or tweaks like “NoAppThinning”.", comment: ""))
                }
                targetMachO = machO
            } catch {
                DDLogError("Unable to locate injection target: \(error)", ddlog: logger)
                for assetURL in machOAssetURLs {
                    outcome.failed.append(
                        InjectFailure(assetURL: assetURL, sourceURL: sourceOf[assetURL] ?? assetURL, stage: .machO, error: error)
                    )
                }
            }

            if let targetMachO {
                for assetURL in machOAssetURLs {
                    do {
                        try applyMachO(assetURL, to: targetMachO, substrateFwkURL: substrateFwkURL)
                        outcome.succeeded.append(assetURL)
                        DDLogInfo("Injected \(assetURL.lastPathComponent)", ddlog: logger)
                    } catch {
                        DDLogError("Inject failed for \(assetURL.lastPathComponent): \(error)", ddlog: logger)
                        outcome.failed.append(
                            InjectFailure(assetURL: assetURL, sourceURL: sourceOf[assetURL] ?? assetURL, stage: .machO, error: error)
                        )
                    }
                }
            }
        }

        // 4. 只持久化成功的插件。
        if shouldPersist, !outcome.succeeded.isEmpty {
            do {
                try persist(outcome.succeeded)
            } catch {
                DDLogError("Persist failed: \(error)", ddlog: logger)
            }
        }

        outcome.didUseFallback = didUseMachOEnumerationFallback
        DDLogInfo(
            "Continue inject finished: \(outcome.succeeded.count) succeeded, \(outcome.failed.count) failed",
            ddlog: logger
        )
        return outcome
    }

    // MARK: - Single Asset Transactions

    /// 提交一个 `.bundle` 插件。
    fileprivate func applyBundle(_ assetURL: URL) throws {
        let targetURL = bundleURL.appendingPathComponent(assetURL.lastPathComponent)
        try cmdCopy(from: assetURL, to: targetURL, clone: true, overwrite: true)
        try cmdChangeOwnerToInstalld(targetURL, recursively: true)
    }

    /// 提交一个 `dylib` / `framework` 插件；失败时只撤销本次改动。
    fileprivate func applyMachO(_ assetURL: URL, to targetMachO: URL, substrateFwkURL: URL?) throws {
        // 插件自身的依赖整理与签名，和宿主无关，失败直接算这个插件失败。
        try standardizeLoadCommandDylibToSubstrate(assetURL)
        try applyCoreTrustBypass(assetURL)

        DDLogInfo("Best matched Mach-O is \(targetMachO.path)", ddlog: logger)

        // 本次是否由我们创建了备份：若失败且没有其它插件落在这个 host 上，
        // 直接恢复备份是最干净的撤销方式（连 LC_RPATH 与签名改动一起还原）。
        let createdAlternate = !hasAlternate(targetMachO)
        try makeAlternate(targetMachO)

        // CydiaSubstrate 是共享资源，只装一次。
        if let substrateFwkURL {
            let installedURL = frameworksDirectoryURL
                .appendingPathComponent(substrateFwkURL.lastPathComponent, isDirectory: true)
            if !FileManager.default.fileExists(atPath: installedURL.path) {
                try copyToFrameworks(substrateFwkURL)
            }
        }

        do {
            try copyToFrameworks(assetURL)
            try insertLoadCommandOfAsset(assetURL, to: targetMachO)
            try applyCoreTrustBypass(targetMachO)
        } catch {
            rollback(assetURL, target: targetMachO, createdAlternate: createdAlternate)
            throw error
        }
    }

    /// 撤销单个插件的改动。
    ///
    /// - 先删掉刚拷进 `Frameworks/` 的资产；
    /// - 再删掉刚插入的 `LC_LOAD_DYLIB`；
    /// - 若这个 host 的备份是本次新建，直接还原备份。
    fileprivate func rollback(_ assetURL: URL, target: URL, createdAlternate: Bool) {
        let copiedURL = frameworksDirectoryURL.appendingPathComponent(assetURL.lastPathComponent)
        try? cmdRemove(copiedURL, recursively: checkIsBundle(assetURL))

        if let name = try? loadCommandNameOfAsset(assetURL) {
            try? cmdRemoveLoadCommandDylib(target, name: name)
        }

        if createdAlternate {
            try? restoreAlternate(target)
            DDLogWarn("Restored \(target.lastPathComponent) from backup", ddlog: logger)
        } else {
            // 其它插件已在这个 host 上生效，只能做“外科手术式”撤销。
            try? cmdCoreTrustBypass(target, teamID: teamID)
            try? cmdChangeOwnerToInstalld(target)
        }
    }

    /// 把资产拷贝到 `Frameworks/` 并交给 installd。
    fileprivate func copyToFrameworks(_ assetURL: URL) throws {
        let targetURL = frameworksDirectoryURL.appendingPathComponent(assetURL.lastPathComponent)
        try cmdCopy(from: assetURL, to: targetURL, clone: true, overwrite: true)
        try cmdChangeOwnerToInstalld(targetURL, recursively: checkIsBundle(assetURL))
    }

    /// 准备 CydiaSubstrate；失败不致命（不使用 substrate 的插件仍可注入）。
    fileprivate func prepareSubstrateIfNeeded() -> URL? {
        do {
            let fwkURL = try prepareSubstrate()
            let installedURL = frameworksDirectoryURL
                .appendingPathComponent(fwkURL.lastPathComponent, isDirectory: true)
            if !FileManager.default.fileExists(atPath: installedURL.path) {
                try copyToFrameworks(fwkURL)
            }
            return fwkURL
        } catch {
            DDLogWarn("Unable to prepare CydiaSubstrate: \(error)", ddlog: logger)
            return nil
        }
    }
}