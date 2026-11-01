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
            let navigationController = LogsView.makeNavigationController(url: url)
            presenter.present(navigationController, animated: true)
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
