//
//  AppDelegate.swift
//  TrollFools
//
//  Ported from TrollFools 4.3-249: `trollfools://` deep-link + home-screen
//  quick-action handling + background daemon bootstrap.
//

import UIKit

/// Opens a managed app from a `trollfools://openManagedApp?bid=<bundle-id>` URL.
@discardableResult
func openManagedAppURL(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "trollfools",
          let host = url.host, host == "openManagedApp"
    else {
        return false
    }

    var bid: String?
    if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
        bid = components.queryItems?.first(where: {
            $0.name == "bid" || $0.name == "id" || $0.name == "bundleIdentifier"
        })?.value
    }
    if bid == nil {
        bid = url.pathComponents.last
    }

    guard let bid, !bid.isEmpty else {
        return false
    }

    LSApplicationWorkspace.default().openApplication(withBundleID: bid)
    return true
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        ShortcutService.shared.refresh()
        if AppManagement.shared.daemonEnabled {
            AutoRestoreManager.shared.start()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        if let bid = ShortcutService.shared.handle(shortcutItem) {
            LSApplicationWorkspace.default().openApplication(withBundleID: bid)
            completionHandler(true)
        } else {
            completionHandler(false)
        }
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        openManagedAppURL(url)
    }
}
