//
//  EjectListModel.swift
//  TrollFools
//
//  Created by 82Flex on 2024/10/30.
//

import Combine
import SwiftUI

/// A pending "change injection target" request raised from the plug-in list.
/// The view observes it and re-applies the plug-in to its new host.
struct RetargetRequest: Equatable {
    let plugIn: InjectedPlugIn
    let previousTarget: InjectionTarget?
    let newTarget: InjectionTarget?
}

final class EjectListModel: ObservableObject {
    let app: App
    private(set) var injectedPlugIns: [InjectedPlugIn] = []

    @Published var filter = FilterOptions()
    @Published var filteredPlugIns: [InjectedPlugIn] = []

    @Published var isOkToEnableAll = false
    @Published var isOkToDisableAll = false

    @Published var processingPlugIn: InjectedPlugIn?

    /// Plug-in whose injection target is currently being edited.
    @Published var targetPickerPlugIn: InjectedPlugIn?

    /// A pending target change to be applied by the view.
    @Published var retargetRequest: RetargetRequest?

    /// Cached injection hosts of this app.
    ///
    /// Scanning `Frameworks/` and `PlugIns/` parses every Mach-O, which is far
    /// too expensive to repeat from a SwiftUI `body` (it used to hang the main
    /// thread and got the app killed by the watchdog). The list is therefore
    /// built once per reload on a background queue.
    @Published private(set) var injectionTargets: [InjectorV3.TargetCandidate]?

    private var isLoadingInjectionTargets = false

    private var cancellables = Set<AnyCancellable>()

    init(_ app: App) {
        self.app = app
        reload()

        $filter
            .throttle(for: 0.5, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.performFilter()
            }
            .store(in: &cancellables)
    }

    func reload() {
        let store = InjectionTargetStore.shared
        let bid = app.bid

        var plugIns = [InjectedPlugIn]()
        plugIns += InjectorV3.main.injectedAssetURLsInBundle(app.url)
            .map {
                InjectedPlugIn(
                    url: $0,
                    isEnabled: true,
                    injectionTarget: store.target(forPlugInName: $0.lastPathComponent, bundleID: bid)
                )
            }

        let enabledNames = plugIns.map { $0.url.lastPathComponent }
        plugIns += InjectorV3.main.persistedAssetURLs(bid: app.bid)
            .filter { !enabledNames.contains($0.lastPathComponent) }
            .map {
                InjectedPlugIn(
                    url: $0,
                    isEnabled: false,
                    injectionTarget: store.target(forPlugInName: $0.lastPathComponent, bundleID: bid)
                )
            }

        injectedPlugIns = plugIns
            .sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }

        performFilter()

        refreshInjectionTargets()
    }

    /// Rebuilds the cached injection-target list off the main thread.
    ///
    /// Every call re-parses the app's Mach-Os, so it must never run from a
    /// SwiftUI `body` evaluation: doing that repeatedly saturated the main
    /// thread and ended in a `0x8badf00d` watchdog termination.
    func refreshInjectionTargets() {
        guard !isLoadingInjectionTargets else {
            return
        }
        isLoadingInjectionTargets = true

        // A fresh list is required after any injection-state change.
        injectionTargets = nil

        let appURL = app.url

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let targets: [InjectorV3.TargetCandidate]
            if let injector = try? InjectorV3(appURL) {
                targets = injector.availableInjectionTargets()
            } else {
                targets = []
            }

            DispatchQueue.main.async {
                guard let self = self else {
                    return
                }
                self.injectionTargets = targets
                self.isLoadingInjectionTargets = false
            }
        }
    }

    func performFilter() {
        var filteredPlugIns = injectedPlugIns

        if !filter.searchKeyword.isEmpty {
            filteredPlugIns = filteredPlugIns.filter {
                $0.url.lastPathComponent.localizedCaseInsensitiveContains(filter.searchKeyword)
            }
        }

        self.filteredPlugIns = filteredPlugIns
        isOkToEnableAll = filteredPlugIns.contains { !$0.isEnabled }
        isOkToDisableAll = filteredPlugIns.contains { $0.isEnabled }
    }

    func togglePlugIn(_ plugIn: InjectedPlugIn, isEnabled: Bool) {
        guard plugIn.isEnabled != isEnabled else {
            return
        }
        processingPlugIn = plugIn
    }

    // MARK: - Injection Targets

    /// All hosts a plug-in of this app can be pinned to.
    ///
    /// Returns the cached list whenever it is available, so the picker sheet
    /// never re-scans the bundle while SwiftUI evaluates `body`. The synchronous
    /// scan only happens when the cache is not ready yet (e.g. the user taps a
    /// cell immediately after the list appears).
    func availableInjectionTargets() -> [InjectorV3.TargetCandidate] {
        if let injectionTargets = injectionTargets {
            return injectionTargets
        }

        guard let injector = try? InjectorV3(app.url) else {
            return []
        }
        return injector.availableInjectionTargets()
    }

    /// Persists the chosen target and asks the view to re-apply the plug-in.
    func changeTarget(_ target: InjectionTarget?, for plugIn: InjectedPlugIn) {
        InjectionTargetStore.shared.setTarget(
            target,
            forPlugInName: plugIn.url.lastPathComponent,
            bundleID: app.bid
        )

        guard target != plugIn.injectionTarget else {
            return
        }

        retargetRequest = RetargetRequest(
            plugIn: plugIn,
            previousTarget: plugIn.injectionTarget,
            newTarget: target
        )
    }
}