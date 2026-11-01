//
//  SuccessView.swift
//  TrollFools
//
//  Created by Lessica on 2024/7/19.
//

import SwiftUI

struct SuccessView: View {

    let title: String
    let subtitle: String?
    let logFileURL: URL?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text(title)
                .font(.title)
                .bold()

            if let subtitle {
                Text(subtitle)
                    .font(.title3)
            }

            if let logFileURL {
                Button {
                    // 直接用 UIKit present，绕开 SwiftUI 的 sheet 桥（iOS 15 上会在转场中崩溃）。
                    LogsPresenter.present(url: logFileURL)
                } label: {
                    Label(NSLocalizedString("View Logs", comment: ""),
                          systemImage: "note.text")
                }
            }
        }
        .padding()
        .multilineTextAlignment(.center)
    }
}

#Preview {
    SuccessView(
        title: "Hello, World!",
        subtitle: nil,
        logFileURL: nil
    )
}
