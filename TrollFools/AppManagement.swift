//
//  AppManagement.swift
//  TrollFools
//
//  Ported from TrollFools 4.3-249: favorites / blacklist / plugin rename /
//  home-screen shortcuts / auto-enable-on-version-change / background daemon /
//  unsupported-apps / alternative-store detection.
//
//  Persistence keys are the exact UserDefaults keys observed in the 4.3 binary.
//

import Combine
import Foundation

final class AppManagement: ObservableObject {
    static let shared = AppManagement()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let favorites = "favorite"
        static let blacklist = "Blacklist"
        static let pluginRenames = "plugInRenames"
        static let pinnedShortcutIds = "pinned_shortcut_ids"
        static let unsupportedApps = "unsupportedApps"
        static let autoEnablePrefix = "AutoEnableOnVersionChange-"
        static let lastKnownVersionPrefix = "LastKnownVersion-"
        static let daemonEnabled = "Daemon"
        static let daemonAlertPresented = "DaemonAlertPresented"
    }

    @Published var favoriteBids: Set<String>
    @Published var blacklistedBids: Set<String>
    @Published var daemonEnabled: Bool

    init() {
        favoriteBids = Set(defaults.stringArray(forKey: Key.favorites) ?? [])
        blacklistedBids = Set(defaults.stringArray(forKey: Key.blacklist) ?? [])
        daemonEnabled = defaults.bool(forKey: Key.daemonEnabled)
    }

    // MARK: - Favorites

    func isFavorite(_ bid: String) -> Bool { favoriteBids.contains(bid) }

    func toggleFavorite(_ bid: String) {
        if favoriteBids.contains(bid) {
            favoriteBids.remove(bid)
        } else {
            favoriteBids.insert(bid)
        }
        defaults.set(Array(favoriteBids), forKey: Key.favorites)
        ShortcutService.shared.refresh()
    }

    // MARK: - Blacklist

    func isBlacklisted(_ bid: String) -> Bool { blacklistedBids.contains(bid) }

    func toggleBlacklist(_ bid: String) {
        if blacklistedBids.contains(bid) {
            blacklistedBids.remove(bid)
        } else {
            blacklistedBids.insert(bid)
        }
        defaults.set(Array(blacklistedBids), forKey: Key.blacklist)
    }

    // MARK: - Plugin rename (备注)

    var pluginRenames: [String: String] {
        defaults.dictionary(forKey: Key.pluginRenames) as? [String: String] ?? [:]
    }

    func renamedPlugIn(_ filename: String) -> String? {
        pluginRenames[filename]
    }

    func setPluginRename(_ name: String?, for filename: String) {
        var dict = pluginRenames
        if let name, !name.isEmpty {
            dict[filename] = name
        } else {
            dict.removeValue(forKey: filename)
        }
        defaults.set(dict, forKey: Key.pluginRenames)
    }

    // MARK: - Home-screen shortcuts (桌面快捷方式)

    var pinnedShortcutIds: [String] {
        defaults.stringArray(forKey: Key.pinnedShortcutIds) ?? []
    }

    func isPinnedShortcut(_ bid: String) -> Bool { pinnedShortcutIds.contains(bid) }

    func setPinnedShortcut(_ bid: String, pinned: Bool) {
        var ids = pinnedShortcutIds
        if pinned {
            if !ids.contains(bid) { ids.append(bid) }
        } else {
            ids.removeAll { $0 == bid }
        }
        defaults.set(ids, forKey: Key.pinnedShortcutIds)
        ShortcutService.shared.refresh()
    }

    // MARK: - Auto-enable on version change (per app)

    func isAutoEnableEnabled(for bid: String) -> Bool {
        defaults.bool(forKey: Key.autoEnablePrefix + bid)
    }

    func setAutoEnable(_ enabled: Bool, for bid: String) {
        defaults.set(enabled, forKey: Key.autoEnablePrefix + bid)
    }

    func lastKnownVersion(for bid: String) -> String? {
        defaults.string(forKey: Key.lastKnownVersionPrefix + bid)
    }

    func setLastKnownVersion(_ version: String?, for bid: String) {
        defaults.set(version, forKey: Key.lastKnownVersionPrefix + bid)
    }

    // MARK: - Unsupported apps

    var unsupportedApps: [String] {
        defaults.stringArray(forKey: Key.unsupportedApps) ?? []
    }

    func setUnsupportedApps(_ bids: [String]) {
        defaults.set(bids, forKey: Key.unsupportedApps)
    }

    // MARK: - Daemon

    var daemonAlertPresented: Bool {
        get { defaults.bool(forKey: Key.daemonAlertPresented) }
        set { defaults.set(newValue, forKey: Key.daemonAlertPresented) }
    }

    // MARK: - Alternative store detection (mirrors 4.3)

    static let hasDopamine = LSApplicationProxy(forIdentifier: "com.opa334.Dopamine") != nil
    static let hasSileo = LSApplicationProxy(forIdentifier: "org.coolstar.SileoStore") != nil
    static let hasZebra = LSApplicationProxy(forIdentifier: "xyz.willy.Zebra") != nil
    static let hasAlternativeStore = hasDopamine || hasSileo || hasZebra
}
