//
//  LogsView.swift
//  TrollFools
//
//  Created by 82Flex on 2025/1/14.
//

import SwiftUI
import UIKit

struct LogsView: UIViewControllerRepresentable {

    let url: URL

    typealias UIViewControllerType = UINavigationController

    /// 构建日志页控制器。抽成静态方法，供 SwiftUI（UIViewControllerRepresentable）
    /// 与 UIKit 直接 present（`LogsPresenter`）共用同一套配置。
    static func makeNavigationController(url: URL) -> UINavigationController {

        let viewController = StripedTextTableViewController(path: url.path)

        viewController.autoReload = false
        viewController.maximumNumberOfRows = 1000
        viewController.maximumNumberOfLines = 20
        viewController.reversed = true
        viewController.allowDismissal = true
        viewController.allowTrash = false
        viewController.allowSearch = true
        viewController.allowShare = true
        viewController.allowMultiline = true
        viewController.pullToReload = false
        viewController.tapToCopy = true
        viewController.pressToCopy = true
        viewController.preserveEmptyLines = false
        viewController.removeDuplicates = true

        if let regex = try? NSRegularExpression(pattern: "^\\d{4}\\/\\d{2}\\/\\d{2} \\d{2}:\\d{2}:\\d{2}:\\d{3}  ") {
            viewController.rowPrefixRegularExpression = regex
        }

        return UINavigationController(rootViewController: viewController)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        Self.makeNavigationController(url: url)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
    }
}

/// 直接用 UIKit present 日志页，绕开 SwiftUI 的 sheet 桥。
///
/// iOS 15 上，当视图树在转场过程中重建（例如注入完成把「注入中」替换成结果页）时，
/// SwiftUI 内部的 `SheetBridge.dismissAndPresentAgain` 会在 `transitionDidFinish`
/// 回调里再调 `presentViewController:`，此时 presenter 仍处于转场状态，
/// UIKit 会抛 `NSInternalInconsistencyException` 导致 SIGABRT。
/// 这里改由我们自己 present，彻底避开该桥接逻辑。
enum LogsPresenter {
    static func present(url: URL) {
        DispatchQueue.main.async {
            guard let presenter = topViewController() else { return }
            // 先立刻呈现一个 loading 占位页，绝不在主线程等待日志读取/解析。
            let placeholder = UIViewController()
            placeholder.view.backgroundColor = .systemBackground
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.translatesAutoresizingMaskIntoConstraints = false
            spinner.startAnimating()
            placeholder.view.addSubview(spinner)
            NSLayoutConstraint.activate([
                spinner.centerXAnchor.constraint(equalTo: placeholder.view.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: placeholder.view.centerYAnchor),
            ])
            placeholder.title = NSLocalizedString("Logs", comment: "")
            let navigationController = UINavigationController(rootViewController: placeholder)
            presenter.present(navigationController, animated: true) {
                // 日志裁剪（只保留尾部）与视图构建都放到后台，避免主线程被打满。
                DispatchQueue.global(qos: .userInitiated).async {
                    let preparedURL = LogTail.prepare(url)
                    DispatchQueue.main.async {
                        let content = LogsView.makeNavigationController(url: preparedURL)
                        if let root = content.viewControllers.first {
                            navigationController.setViewControllers([root], animated: false)
                        }
                    }
                }
            }
        }
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        guard let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first else {
            return nil
        }

        var controller = window.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        if let navigation = controller as? UINavigationController {
            controller = navigation.visibleViewController ?? navigation
        } else if let tab = controller as? UITabBarController {
            controller = tab.selectedViewController ?? tab
        }
        // 不要试图在 UIAlertController 之上 present。
        if controller is UIAlertController {
            controller = controller?.presentingViewController ?? controller
        }
        return controller
    }
}

/// 把过大的日志裁剪成「尾部 N KB」的临时文件后再交给日志页。
///
/// CocoaLumberjack 默认单个日志文件上限 1 MB，但历史文件、外部写入或第三方
/// 追加都可能让文件变大；在主线程整份读取 + 去重 + 正则处理会长时间占满
/// 主线程，进而触发 iOS 15 的 `scene-update` 看门狗（`0x8badf00d`）。
enum LogTail {
    /// 最多保留的字节数。
    static let maximumBytes = 512 * 1024

    static func prepare(_ url: URL) -> URL {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let number = attributes[.size] as? NSNumber
        else {
            return url
        }
        let size = number.intValue
        guard size > maximumBytes else {
            return url
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return url
        }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: UInt64(size - maximumBytes))) != nil,
              let tail = try? handle.readDataToEndOfFile()
        else {
            return url
        }
        // 丢掉可能被截断的第一行。
        var data = tail
        if let newline = data.firstIndex(of: 0x0A), newline + 1 < data.count {
            data = data.subdata(in: (newline + 1) ..< data.count)
        }
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TrollFools-recent.log")
        guard (try? data.write(to: destination, options: .atomic)) != nil else {
            return url
        }
        return destination
    }
}
