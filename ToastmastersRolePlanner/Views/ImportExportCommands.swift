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
/// provides actions (i.e. the Members, Meetings, or Templates view is showing).
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

/// Action published by the Templates view to duplicate the selected template.
struct TemplateMenuActions {
    var duplicate: () -> Void
}

extension FocusedValues {
    struct TemplateMenuKey: FocusedValueKey {
        typealias Value = TemplateMenuActions
    }

    var templateMenu: TemplateMenuActions? {
        get { self[TemplateMenuKey.self] }
        set { self[TemplateMenuKey.self] = newValue }
    }
}

/// File menu item to duplicate the selected meeting template.
struct TemplateCommands: Commands {
    @FocusedValue(\.templateMenu) private var actions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Duplicate Template") { actions?.duplicate() }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(actions == nil)
        }
    }
}
