//
//  UnsupportedAppListView.swift
//  TrollFools
//
//  Ported from TrollFools 4.3-249: dedicated list of unsupported applications.
//

import SwiftUI

struct UnsupportedAppListView: View {
    let bids: [String]

    var body: some View {
        List {
            Section(header: Text(NSLocalizedString("Other", comment: "")).textCase(.none)) {
                ForEach(bids, id: \.self) { bid in
                    HStack {
                        if #available(iOS 15, *) {
                            Image(uiImage: UIImage._applicationIconImage(forBundleIdentifier: bid, format: 0, scale: 3.0) ?? UIImage())
                                .resizable()
                                .frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }

                        Text(bid)
                            .font(.subheadline)
                            .lineLimit(1)

                        Spacer()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Unsupported Applications", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
}
