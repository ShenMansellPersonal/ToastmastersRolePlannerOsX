import SwiftUI

/// Import/export actions published by whichever view currently supports them
/// (Members, Meetings…). The menu-bar commands read these via focused values.
struct ImportExportActions {
    var exportTitle: String
    var importTitle: String
    var exportAction: () -> Void
    var importAction: () -> Void
}

extension FocusedValues {
    struct ImportExportKey: FocusedValueKey {
        typealias Value = ImportExportActions
    }

    var importExport: ImportExportActions? {
        get { self[ImportExportKey.self] }
        set { self[ImportExportKey.self] = newValue }
    }
}

/// File ▸ Import / Export menu items. Enabled only when the focused scene
/// provides actions (i.e. the Members or Meetings view is showing).
struct ImportExportCommands: Commands {
    @FocusedValue(\.importExport) private var actions

    var body: some Commands {
        CommandGroup(replacing: .importExport) {
            Button(actions?.exportTitle ?? "Export…") { actions?.exportAction() }
                .disabled(actions == nil)
            Button(actions?.importTitle ?? "Import…") { actions?.importAction() }
                .disabled(actions == nil)
        }
    }
}
