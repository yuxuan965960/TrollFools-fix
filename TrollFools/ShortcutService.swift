//
//  ShortcutService.swift
//  TrollFools
//
//  Ported from TrollFools 4.3-249: home-screen quick actions for pinned apps.
//

import UIKit

final class ShortcutService {
    static let shared = ShortcutService()

    static let openManagedAppType = "wiki.qaq.TrollFools.openManagedApp"
    static let bidUserInfoKey = "bid"

    private init() {}

    /// Rebuilds `UIApplication.shortcutItems` from the pinned app IDs.
    func refresh() {
        let bids = AppManagement.shared.pinnedShortcutIds

        guard !bids.isEmpty else {
            UIApplication.shared.shortcutItems = nil
            return
        }

        UIApplication.shared.shortcutItems = bids.prefix(4).map { bid in
            let title = LSApplicationProxy(forIdentifier: bid)?.localizedName() ?? bid
            return UIApplicationShortcutItem(
                type: Self.openManagedAppType,
                localizedTitle: title,
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(type: .play),
                userInfo: [Self.bidUserInfoKey: bid] as [String: NSSecureCoding]
            )
        }
    }

    /// Handles a quick-action tap and returns the bundle id to open, if any.
    func handle(_ shortcutItem: UIApplicationShortcutItem) -> String? {
        guard shortcutItem.type == Self.openManagedAppType else {
            return nil
        }
        return shortcutItem.userInfo?[Self.bidUserInfoKey] as? String
    }
}
