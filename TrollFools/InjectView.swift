//
//  InjectView.swift
//  TrollFools
//
//  Created by Lessica on 2024/7/19.
//

import CocoaLumberjackSwift
import SwiftUI

struct InjectView: View {
    @EnvironmentObject var appList: AppListModel

    let app: App
    let urlList: [URL]

    /// 本次（可能是多次连续的）注入结果。
    @State private var outcome: InjectorV3.InjectOutcome?
    /// 致命错误（例如目标 App 的 Bundle 打不开）。
    @State private var fatalError: Error?
    /// 是否正在注入（含「继续注入」）。
    @State private var isInjecting = true
    /// 最新日志文件。
    @State private var logFileURL: URL?
    /// 是否已经启动过首轮注入，避免重复触发。
    @State private var hasStarted = false

    @StateObject fileprivate var viewControllerHost = ViewControllerHost()

    @AppStorage var useWeakReference: Bool
    @AppStorage var preferMainExecutable: Bool
    @AppStorage var useFrameworkEnumerationFallback: Bool
    @AppStorage var injectStrategy: InjectorV3.Strategy

    init(_ app: App, urlList: [URL]) {
        self.app = app
        self.urlList = urlList
        _useWeakReference = AppStorage(wrappedValue: true, "UseWeakReference-\(app.bid)")
        _preferMainExecutable = AppStorage(wrappedValue: false, "PreferMainExecutable-\(app.bid)")
        _useFrameworkEnumerationFallback = AppStorage(wrappedValue: true, "UseFrameworkEnumerationFallback-\(app.bid)")
        _injectStrategy = AppStorage(wrappedValue: .lexicographic, "InjectStrategy-\(app.bid)")
    }

    var body: some View {
        if appList.isSelectorMode {
            bodyContent
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(NSLocalizedString("Done", comment: "")) {
                            viewControllerHost.viewController?.navigationController?
                                .dismiss(animated: true)
                        }
                    }
                }
        } else {
            bodyContent
        }
    }

    var bodyContent: some View {
        VStack {
            if isInjecting {
                if #available(iOS 16, *) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding(.all, 20)
                        .controlSize(.large)
                } else {
                    // Fallback on earlier versions
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding(.all, 20)
                        .scaleEffect(2.0)
                }

                Text(NSLocalizedString("Injecting", comment: ""))
                    .font(.headline)
            } else if let fatalError {
                FailureView(
                    title: NSLocalizedString("Failed", comment: ""),
                    error: fatalError,
                    details: outcome?.failureDetails,
                    retryTitle: retryTitle,
                    onRetry: retryAction
                )
                .onAppear {
                    app.reload()
                }
            } else if let outcome {
                if outcome.isComplete {
                    SuccessView(
                        title: NSLocalizedString("Completed", comment: ""),
                        subtitle: outcome.didUseFallback
                            ? NSLocalizedString("Completed with compatibility mode. The plug-in may start working after opening some app features.", comment: "")
                            : nil,
                        logFileURL: logFileURL
                    )
                    .onAppear {
                        app.reload()
                    }
                } else {
                    // 部分成功 / 全部失败：展示失败清单，并提供「继续注入」。
                    FailureView(
                        title: NSLocalizedString(
                            outcome.isPartial ? "Partially Completed" : "Failed",
                            comment: ""
                        ),
                        error: nsError(for: outcome),
                        details: outcome.failureDetails,
                        retryTitle: retryTitle,
                        onRetry: retryAction
                    )
                    .onAppear {
                        app.reload()
                    }
                }
            } else {
                Text(NSLocalizedString("Failed", comment: ""))
                    .font(.headline)
            }
        }
        .padding()
        .animation(.easeOut, value: isInjecting)
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .onViewWillAppear { viewController in
            viewController.navigationController?
                .view.isUserInteractionEnabled = false
            viewControllerHost.viewController = viewController
        }
        .onAppear {
            guard !hasStarted else {
                return
            }
            hasStarted = true
            run(urlList, mergesResult: false)
        }
    }

    // MARK: - Continue Injection

    /// 可以继续注入的插件（即上一轮失败的插件）。
    private var retryableURLs: [URL] {
        outcome?.failedAssetURLs ?? []
    }

    private var retryTitle: String? {
        retryableURLs.isEmpty ? nil : NSLocalizedString("Continue Inject", comment: "")
    }

    private var retryAction: (() -> Void)? {
        guard !retryableURLs.isEmpty else {
            return nil
        }
        return { self.continueInjecting() }
    }

    /// 「继续注入」：只重试失败的插件，成功结果累加。
    private func continueInjecting() {
        let urls = retryableURLs
        guard !urls.isEmpty else {
            return
        }
        run(urls, mergesResult: true)
    }

    // MARK: - Injection

    private func run(_ urls: [URL], mergesResult: Bool) {
        guard !urls.isEmpty else {
            isInjecting = false
            return
        }

        isInjecting = true

        DispatchQueue.global(qos: .userInitiated).async {
            var newOutcome: InjectorV3.InjectOutcome?
            var thrown: Error?
            var latestLogURL: URL?

            do {
                let injector = try makeInjector()
                latestLogURL = injector.latestLogFileURL

                newOutcome = injector.injectContinuing(urls, shouldPersist: true)
                latestLogURL = injector.latestLogFileURL ?? latestLogURL
            } catch {
                thrown = error
            }

            DispatchQueue.main.async {
                isInjecting = false
                if let latestLogURL {
                    logFileURL = latestLogURL
                }

                if let thrown {
                    DDLogError("\(thrown)", ddlog: InjectorV3.main.logger)
                    fatalError = makeNSError(thrown, logFileURL: latestLogURL)
                }

                if let newOutcome {
                    if mergesResult, var accumulated = outcome {
                        accumulated.merge(newOutcome)
                        outcome = accumulated
                    } else {
                        outcome = newOutcome
                    }
                }

                app.reload()
                viewControllerHost.viewController?.navigationController?
                    .view.isUserInteractionEnabled = true
            }
        }
    }

    private func makeInjector() throws -> InjectorV3 {
        let injector = try InjectorV3(app.url)

        if injector.appID.isEmpty {
            injector.appID = app.bid
        }

        if injector.teamID.isEmpty {
            injector.teamID = app.teamID
        }

        injector.useWeakReference = useWeakReference
        injector.preferMainExecutable = preferMainExecutable
        injector.useFrameworkEnumerationFallback = useFrameworkEnumerationFallback
        injector.injectStrategy = injectStrategy

        return injector
    }

    private func makeNSError(_ error: Error, logFileURL: URL?) -> NSError {
        var userInfo: [String: Any] = [
            NSLocalizedDescriptionKey: error.localizedDescription,
        ]

        if let logFileURL {
            userInfo[NSURLErrorKey] = logFileURL
        }

        return NSError(domain: Constants.gErrorDomain, code: 0, userInfo: userInfo)
    }

    /// 用第一条失败信息构造展示用的 NSError（附带日志文件）。
    private func nsError(for outcome: InjectorV3.InjectOutcome) -> Error {
        guard let first = outcome.failed.first else {
            return makeNSError(InjectorV3.Error.generic(
                NSLocalizedString("Failed", comment: "")
            ), logFileURL: logFileURL)
        }
        return makeNSError(first.error, logFileURL: logFileURL)
    }
}