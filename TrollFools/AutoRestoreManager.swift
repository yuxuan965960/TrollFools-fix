//
//  AutoRestoreManager.swift
//  TrollFools
//
//  Ported from TrollFools 4.3-249: background auto-restore. Detects app version
//  changes and re-enables persisted plug-ins when the daemon is running.
//

import Combine
import Foundation
import notify
import UserNotifications

final class AutoRestoreManager {
    static let shared = AutoRestoreManager()

    private var darwinNotifyToken: Int32 = NOTIFY_TOKEN_INVALID
    private let applicationChanged = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()

    private init() {
        applicationChanged
            .throttle(for: 2.0, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.checkAllApps()
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    func start() {
        stop()

        notify_register_dispatch("com.apple.LaunchServices.ApplicationsChanged", &darwinNotifyToken, .main) { [weak self] _ in
            self?.applicationChanged.send()
        }

        requestNotificationAuthorizationIfNeeded()
        checkAllApps()
    }

    func stop() {
        if darwinNotifyToken != NOTIFY_TOKEN_INVALID {
            notify_cancel(darwinNotifyToken)
            darwinNotifyToken = NOTIFY_TOKEN_INVALID
        }
    }

    // MARK: - Version tracking + restore

    func checkAllApps() {
        guard AppManagement.shared.daemonEnabled else {
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let proxies = LSApplicationWorkspace.default().allApplications()
            for proxy in proxies ?? [] {
                guard let bid = proxy.applicationIdentifier(),
                      let url = proxy.bundleURL(),
                      let version = proxy.shortVersionString()
                else {
                    continue
                }

                self.restoreIfNeeded(bid: bid, url: url, version: version)
            }
        }
    }

    private func restoreIfNeeded(bid: String, url: URL, version: String) {
        let management = AppManagement.shared
        guard management.isAutoEnableEnabled(for: bid) else {
            management.setLastKnownVersion(version, for: bid)
            return
        }

        let lastKnown = management.lastKnownVersion(for: bid)
        management.setLastKnownVersion(version, for: bid)

        // First run: nothing to compare against, just record the version.
        guard let lastKnown, lastKnown != version else {
            return
        }

        let persistedURLs = InjectorV3.main.persistedAssetURLs(bid: bid)
        guard !persistedURLs.isEmpty else {
            return
        }

        do {
            let injector = try InjectorV3(url)
            if injector.appID.isEmpty { injector.appID = bid }
            if injector.teamID.isEmpty { injector.teamID = proxyTeamID(for: bid) }
            injector.useWeakReference = true
            injector.useFrameworkEnumerationFallback = true

            try injector.inject(persistedURLs, shouldPersist: false)
            postRestoreNotification(for: bid)
        } catch {
            // Restore failures are intentionally non-fatal in the background.
        }
    }

    private func proxyTeamID(for bid: String) -> String {
        LSApplicationProxy(forIdentifier: bid)?.teamID() ?? ""
    }

    // MARK: - Local notification

    private func requestNotificationAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }
        }
    }

    private func postRestoreNotification(for bid: String) {
        let appName = LSApplicationProxy(forIdentifier: bid)?.localizedName() ?? bid

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Auto Restore", comment: "")
        content.body = String(
            format: NSLocalizedString("Successfully restored plugins for \"%@\"", comment: ""),
            appName
        )
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "TF-Restore-Start-\(bid)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
