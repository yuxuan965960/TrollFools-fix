//
//  RenameSheetView.swift
//  TrollFools
//
//  Ported from TrollFools 4.3-249: custom-name (备注) editor for plug-ins.
//

import SwiftUI

struct RenameSheetView: View {
    let pluginFilename: String
    let onSave: (String?) -> Void

    @State private var newName: String
    @Environment(\.presentationMode) private var presentationMode

    init(pluginFilename: String, currentName: String?, onSave: @escaping (String?) -> Void) {
        self.pluginFilename = pluginFilename
        self.onSave = onSave
        _newName = State(initialValue: currentName ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section(footer: Text(NSLocalizedString("Leave it empty to restore the original name.", comment: ""))) {
                    TextField(NSLocalizedString("Custom Name", comment: ""), text: $newName)
                }
            }
            .navigationTitle(NSLocalizedString("Rename", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Save", comment: "")) {
                        onSave(newName.isEmpty ? nil : newName)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}
