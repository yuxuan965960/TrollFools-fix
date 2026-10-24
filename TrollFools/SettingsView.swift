//
//  SettingsView.swift
//  TrollFools
//
//  Created by Lessica on 2024/7/28.
//

import SwiftUI

struct SettingsView: View {
    let app: App

    init(_ app: App) {
        self.app = app
        _useWeakReference = AppStorage(wrappedValue: true, "UseWeakReference-\(app.bid)")
        _preferMainExecutable = AppStorage(wrappedValue: false, "PreferMainExecutable-\(app.bid)")
        _useFrameworkEnumerationFallback = AppStorage(wrappedValue: true, "UseFrameworkEnumerationFallback-\(app.bid)")
        _injectStrategy = AppStorage(wrappedValue: .lexicographic, "InjectStrategy-\(app.bid)")
    }

    @AppStorage var useWeakReference: Bool
    @AppStorage var preferMainExecutable: Bool
    @AppStorage var useFrameworkEnumerationFallback: Bool
    @AppStorage var injectStrategy: InjectorV3.Strategy

    @StateObject var viewControllerHost = ViewControllerHost()
    @ObservedObject private var management = AppManagement.shared

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker(NSLocalizedString("Injection Strategy", comment: ""), selection: $injectStrategy) {
                        ForEach(InjectorV3.Strategy.allCases, id: \.self) { strategy in
                            Text(strategy.localizedDescription).tag(strategy)
                        }
                    }
                } footer: {
                    paddedHeaderFooterText(NSLocalizedString("Choose how TrollFools tries possible targets. If the plug-in does not work as expected, try another option.", comment: ""))
                }

                Section {
                    Toggle(NSLocalizedString("Enable Compatibility Fallback", comment: ""), isOn: $useFrameworkEnumerationFallback)
                } footer: {
                    paddedHeaderFooterText(NSLocalizedString("If needed, TrollFools will use a compatibility mode to improve success rate. Keeping this on is recommended.", comment: ""))
                }

                Section {
                    Toggle(NSLocalizedString("Prefer Main Executable", comment: ""), isOn: $preferMainExecutable)
                } footer: {
                    paddedHeaderFooterText(NSLocalizedString("Try the app’s main file first. Turn this on when the plug-in does not seem active.", comment: ""))
                }

                Section {
                    Toggle(NSLocalizedString("Use Weak Reference", comment: ""), isOn: $useWeakReference)
                } footer: {
                    paddedHeaderFooterText(NSLocalizedString("Controls whether the app crashes when the plug-in cannot be found. Keeping this on can reduce unexpected crashes in some scenarios, but the plug-in will not work in those cases.", comment: ""))
                }

                Section {
                    Toggle(NSLocalizedString("Background Daemon", comment: ""), isOn: $management.daemonEnabled)
                } footer: {
                    paddedHeaderFooterText(management.daemonEnabled
                        ? NSLocalizedString("The daemon is running and will monitor app updates in the background.", comment: "")
                        : NSLocalizedString("The daemon is stopped. TrollFools won't auto-inject until you open the app.", comment: ""))
                }

                Section {
                    Toggle(
                        NSLocalizedString("Auto Enable on Version Change", comment: ""),
                        isOn: Binding(
                            get: { management.isAutoEnableEnabled(for: app.bid) },
                            set: { management.setAutoEnable($0, for: app.bid) }
                        )
                    )
                } footer: {
                    paddedHeaderFooterText(NSLocalizedString("Choose whether to automatically enable plug-ins by default when an application updates.", comment: ""))
                }
            }
            .onChange(of: management.daemonEnabled) { enabled in
                if enabled {
                    AutoRestoreManager.shared.start()
                } else {
                    AutoRestoreManager.shared.stop()
                }
            }
            .navigationTitle(NSLocalizedString("Advanced Settings", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .onViewWillAppear {
                viewControllerHost.viewController = $0
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        viewControllerHost.viewController?.dismiss(animated: true)
                    } label: {
                        Text(NSLocalizedString("Done", comment: ""))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func paddedHeaderFooterText(_ content: String) -> some View {
        if #available(iOS 15, *) {
            Text(content)
                .font(.footnote)
        } else {
            Text(content)
                .font(.footnote)
                .padding(.horizontal, 16)
        }
    }
}
