//
//  FailureView.swift
//  TrollFools
//
//  Created by Lessica on 2024/7/19.
//

import SwiftUI

struct FailureView: View {

    let title: String
    let error: Error?

    /// 额外的多行说明，例如失败的插件清单。
    var details: String? = nil

    /// 重试按钮的标题；为 nil 时不显示重试按钮。
    var retryTitle: String? = nil

    /// 重试回调（「继续注入」）。
    var onRetry: (() -> Void)? = nil

    var logFileURL: URL? {
        (error as? NSError)?.userInfo[NSURLErrorKey] as? URL
    }

    @State private var isLogsPresented = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.red)

            Text(title)
                .font(.title)
                .bold()

            if let error {
                Text(error.localizedDescription)
                    .font(.title3)
            }

            if let details, !details.isEmpty {
                ScrollView {
                    Text(details)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }

            if let retryTitle, let onRetry {
                Button(action: onRetry) {
                    Label(retryTitle, systemImage: AppSymbol.continueInject)
                        .font(.headline)
                }
                .prominentButtonStyleCompat()
            }

            if logFileURL != nil {
                Button {
                    isLogsPresented = true
                } label: {
                    Label(NSLocalizedString("View Logs", comment: ""),
                          systemImage: "note.text")
                }
            }
        }
        .padding()
        .multilineTextAlignment(.center)
        .sheet(isPresented: $isLogsPresented) {
            if let logFileURL {
                LogsView(url: logFileURL)
            }
        }
    }
}

extension View {
    /// `.borderedProminent` 为 iOS 15+ API；iOS 14 回退 `BorderlessButtonStyle`。
    @ViewBuilder
    func prominentButtonStyleCompat() -> some View {
        if #available(iOS 15.0, *) {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(BorderlessButtonStyle())
        }
    }
}

#Preview {
    FailureView(
        title: "Hello, World!",
        error: nil
    )
}