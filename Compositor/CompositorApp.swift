import SwiftUI
import Sparkle

@main
struct CompositorApp: App {
    @NSApplicationDelegateAdaptor(CompositorApplicationDelegate.self) private var applicationDelegate
    private var session: EditorSession { applicationDelegate.session }
    var body: some Scene {
        Window("Compositor", id: "editor") {
            ProjectWorkspaceView(applicationDelegate: applicationDelegate).roundedControls()
        }
            .defaultSize(width: 1180, height: 780)
            // Files opened from Finder or dropped on the Dock icon go to the app delegate, which imports them into
            // the open window. Left to SwiftUI, each one builds a throwaway window and fades the editor out and back.
            .handlesExternalEvents(matching: [])
            // A first launch fills the screen (without going full screen); after that macOS reopens the window at the
            // size it was left.
            .defaultWindowPlacement { _, context in
                WindowPlacement(size: context.defaultDisplay.visibleRect.size)
            }
            // The project's name is already on its tab, so the toolbar doesn't repeat it as a window title.
            .windowToolbarStyle(.unifiedCompact(showsTitle: false))
            .commands {
                CommandGroup(replacing: .undoRedo) {
                    // Dialog text fields keep native text undo; document history
                    // is unavailable while an import or modal edit is active.
                    if session.textDraft != nil || session.levels != nil || session.isProjectBusy || session.showsNewDocument || session.showsImporter || session.renamingLayerID != nil || session.transformEdit?.persistent == true {
                        Button("Undo") {
                            if NSApp.keyWindow?.firstResponder is NSTextView {
                                NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                            }
                        }
                            .configuredKeyboardShortcut("z")
                        Button("Redo") {
                            if NSApp.keyWindow?.firstResponder is NSTextView {
                                NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                            }
                        }
                            .configuredKeyboardShortcut("z", modifiers: [.command, .shift])
                    } else {
                        Button(session.history.canUndo ? "Undo \(session.history.undoName)" : "Undo") { session.undo() }
                            .configuredKeyboardShortcut("z").disabled(!session.canUndo)
                        Button(session.history.canRedo ? "Redo \(session.history.redoName)" : "Redo") { session.redo() }
                            .configuredKeyboardShortcut("z", modifiers: [.command, .shift]).disabled(!session.canRedo)
                    }
                }
                CommandGroup(replacing: .newItem) {
                    Button("New Canvas…") {
                        applicationDelegate.showEditor?()
                        Task { await applicationDelegate.projects.newCanvas() }
                    }.configuredKeyboardShortcut("n")
                        .disabled(!applicationDelegate.projects.canRequestStart)
                    Button("Open Project…") {
                        applicationDelegate.showEditor?()
                        Task { await applicationDelegate.projects.open() }
                    }
                        .configuredKeyboardShortcut("o").disabled(!applicationDelegate.projects.canRequestStart)
                    Menu("Open Recent") {
                        ForEach(RecentProjects.shared.urls, id: \.self) { url in
                            Button(url.deletingPathExtension().lastPathComponent) {
                                applicationDelegate.showEditor?()
                                Task { await applicationDelegate.projects.open(url) }
                            }
                        }
                        Divider()
                        Button("Clear Menu") { RecentProjects.shared.clear() }
                            .disabled(RecentProjects.shared.urls.isEmpty)
                    }
                        .disabled(!applicationDelegate.projects.canRequestStart)
                    Button("Import Images…") { if session.prepareForOutsideDocumentAction() { session.showsImporter = true } }
                        .disabled(session.levels != nil || session.showsBusy || session.isImporting || session.showsNewDocument)
                }
                CommandGroup(replacing: .saveItem) {
                    Button("Save") { Task { await applicationDelegate.projects.save() } }
                        .configuredKeyboardShortcut("s").disabled(session.document == nil || !applicationDelegate.projects.canRequestStart)
                    Button("Save As…") { Task { await applicationDelegate.projects.save(asNew: true) } }
                        .configuredKeyboardShortcut("s", modifiers: [.command, .shift])
                        .disabled(session.document == nil || !applicationDelegate.projects.canRequestStart)
                    Divider()
                    Button("Export PNG…") { Task { await applicationDelegate.projects.exportPNG() } }
                        .configuredKeyboardShortcut("e", modifiers: [.command, .shift])
                        .disabled(session.document == nil || !applicationDelegate.projects.canRequestStart)
                    Button("Export JPEG…") { Task { await applicationDelegate.projects.exportJPEG() } }
                        .configuredKeyboardShortcut("s", modifiers: [.command, .option, .shift])
                        .disabled(session.document == nil || !applicationDelegate.projects.canRequestStart)
                    Divider()
                    Button("Close Project") {
                        if let window = applicationDelegate.projects.window {
                            Task { await applicationDelegate.projects.close(window) }
                        }
                    }.configuredKeyboardShortcut("w").disabled(!applicationDelegate.projects.canRequestStart)
                }
                // Grouped: a commands builder takes at most ten items.
                Group {
                    CommandGroup(after: .appInfo) {
                        Button("Check for Updates…") { applicationDelegate.updater.checkForUpdates(nil) }
                    }
                    CommandGroup(after: .toolbar) {
                        Button("Fit Canvas") { session.fit() }.configuredKeyboardShortcut("0").disabled(session.document == nil)
                        Button("Actual Pixels") { session.zoom(to: 1) }.configuredKeyboardShortcut("1").disabled(session.document == nil)
                        Button("Zoom In") {
                            guard !(NSApp.keyWindow?.firstResponder is NSText) else { return }
                            session.zoomKeyboard(by: 1)
                        }
                            .configuredKeyboardShortcut("=").disabled(session.document == nil)
                        Button("Zoom Out") {
                            guard !(NSApp.keyWindow?.firstResponder is NSText) else { return }
                            session.zoomKeyboard(by: -1)
                        }
                            .configuredKeyboardShortcut("-").disabled(session.document == nil)
                        Toggle("Pixel Grid (800% and above)", isOn: Binding(get: { session.showsPixelGrid },
                                                                              set: { session.showsPixelGrid = $0 }))
                        Toggle("Snap", isOn: Binding(get: { session.snappingEnabled },
                                                     set: { session.snappingEnabled = $0 }))
                        Toggle("Show Transform Controls", isOn: Binding(get: { session.showsTransformControls },
                                                                          set: { session.showsTransformControls = $0 }))
                            .configuredKeyboardShortcut("h").disabled(session.tool != .move || session.document == nil)
                        Group {
                            Divider()
                            Menu("Show") {
                                Toggle("Grid", isOn: Binding(get: { session.showsGrid }, set: { session.showsGrid = $0 }))
                                    .configuredKeyboardShortcut("'").disabled(session.document == nil)
                                Toggle("Guides", isOn: Binding(get: { session.showsGuides }, set: { session.showsGuides = $0 }))
                                    .configuredKeyboardShortcut(";").disabled(session.document == nil)
                            }
                            Toggle("Rulers", isOn: Binding(get: { session.showsRulers }, set: { session.showsRulers = $0 }))
                                .configuredKeyboardShortcut("r").disabled(session.document == nil)
                            Divider()
                            Toggle("Snap", isOn: Binding(get: { session.snapEnabled }, set: { session.snapEnabled = $0 }))
                                .configuredKeyboardShortcut(";", modifiers: [.command, .shift]).disabled(session.document == nil)
                            Menu("Snap To") {
                                Toggle("Guides", isOn: Binding(get: { session.snapToGuides }, set: { session.snapToGuides = $0 }))
                                    .disabled(session.document == nil)
                                Toggle("Grid", isOn: Binding(get: { session.snapToGrid }, set: { session.snapToGrid = $0 }))
                                    .disabled(session.document == nil)
                                Toggle("Layers", isOn: Binding(get: { session.snapToLayers }, set: { session.snapToLayers = $0 }))
                                    .disabled(session.document == nil)
                                Toggle("Document Bounds", isOn: Binding(get: { session.snapToDocumentBounds },
                                                                        set: { session.snapToDocumentBounds = $0 }))
                                    .disabled(session.document == nil)
                            }
                            Divider()
                            Toggle("Lock Guides", isOn: Binding(get: { session.locksGuides }, set: { session.locksGuides = $0 }))
                                .configuredKeyboardShortcut(";", modifiers: [.command, .option]).disabled(session.document == nil)
                            Button("Clear Guides") { session.clearGuides() }
                                .disabled(!session.canClearGuides)
                        }
                    }
                    // ⌘H toggles the Move tool's transform controls instead of hiding the app, so Hide keeps its
                    // place in the app menu without the shortcut.
                    CommandGroup(replacing: .appVisibility) {
                        Button("Hide Compositor") { NSApp.hide(nil) }
                        Button("Hide Others") { NSApp.hideOtherApplications(nil) }
                            .configuredKeyboardShortcut("h", modifiers: [.command, .option])
                        Button("Show All") { NSApp.unhideAllApplications(nil) }
                    }
                }
                CommandGroup(replacing: .pasteboard) {
                    // Canvas pixels when the canvas has focus; text fields keep their own editing.
                    // Cut, Copy and Paste check when chosen rather than through .disabled: what they depend on
                    // (the pasteboard, the copied pixels, the busy flag) isn't observed, so a disabled state could
                    // go stale — the first Paste after a Copy used to beep until something else refreshed the menu.
                    Button("Cut") {
                        if NSApp.keyWindow?.firstResponder is NSTextView { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                        else if session.selection != nil, session.canRequestCopyPixels { Task { await session.cutSelection() } }
                        else { NSSound.beep() }
                    }
                        .configuredKeyboardShortcut("x")
                    Button("Copy") {
                        if NSApp.keyWindow?.firstResponder is NSTextView { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
                        else if session.canRequestCopyPixels || session.canRequestCopyLayer { session.copySelection() }
                        else { NSSound.beep() }
                    }
                        .configuredKeyboardShortcut("c")
                    Button("Copy Merged") { session.copyMergedSelection() }
                        .configuredKeyboardShortcut("c", modifiers: [.command, .shift]).disabled(!session.canRequestCopyMerged)
                    Button("Paste") {
                        if NSApp.keyWindow?.firstResponder is NSTextView { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
                        else if session.prepareForOutsideDocumentAction() {
                            if applicationDelegate.workspace.pasteCopiedLayer() { }
                            else if session.canPaste { session.paste() }
                            else { NSSound.beep() }
                        }
                    }
                        .configuredKeyboardShortcut("v")
                }
                CommandGroup(after: .pasteboard) {
                    Divider()
                    Button("Keyboard Shortcuts…") { ShortcutSettings.shared.show() }
                    // Photoshop's fill shortcuts; in a text field they keep their text meaning.
                    Button("Fill with Foreground Color") {
                        if NSApp.keyWindow?.firstResponder is NSTextView {
                            NSApp.sendAction(#selector(NSResponder.deleteWordBackward(_:)), to: nil, from: nil)
                        } else { Task { await session.fillSelection(with: .foreground) } }
                    }
                        .configuredKeyboardShortcut(.delete, modifiers: .option).disabled(!session.canRequestPixelEdit && session.textDraft == nil)
                    Button("Fill with Background Color") {
                        if NSApp.keyWindow?.firstResponder is NSTextView {
                            NSApp.sendAction(#selector(NSResponder.deleteToBeginningOfLine(_:)), to: nil, from: nil)
                        } else { Task { await session.fillSelection(with: .background) } }
                    }
                        .configuredKeyboardShortcut(.delete, modifiers: .command).disabled(!session.canRequestPixelEdit && session.textDraft == nil)
                    Button("Clear Selection Pixels") { Task { await session.clearSelectedPixels() } }
                        .disabled(session.selection == nil || !session.canRequestPixelEdit)
                    Button("Content-Aware Fill…") { session.beginFilter(.contentAwareFill) }
                        .configuredKeyboardShortcut(.delete, modifiers: .shift).disabled(!session.canRequestContentAwareFill)
                }
                CommandMenu("Select") {
                    // A field being edited keeps its own Select All: offer it to the responder chain
                    // first, which covers every kind of text control rather than NSTextView alone,
                    // and select the canvas only when nothing there wanted it.
                    Button("All") {
                        if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) { return }
                        guard session.document != nil else { return }
                        session.selectAll()
                    }
                        // Never disabled: on macOS this menu item is what binds Cmd-A to selectAll:, so
                        // switching it off takes Select All away from every text field too. With no
                        // document and nothing being edited the action simply does nothing.
                        .configuredKeyboardShortcut("a")
                    Button("Deselect") { session.deselect() }
                        .configuredKeyboardShortcut("d").disabled(session.selection == nil || !session.canRequestSelectionEdit)
                    Button("Inverse") { session.invertSelection() }
                        .configuredKeyboardShortcut("i", modifiers: [.command, .shift])
                        .disabled(session.selection == nil || !session.canRequestSelectionEdit)
                    Button("Layer's Pixels") {
                        if session.prepareForOutsideDocumentAction(), let id = session.activeLayerID { session.loadLayerSelection(layerID: id) }
                    }
                        .disabled((session.activeLayer?.asset == nil && !session.hasCommittableNewTextDraft) || !session.canRequestSelectionEdit)
                    Button("Subject") { Task { await session.selectSubject() } }
                        .configuredKeyboardShortcut("a", modifiers: [.command, .option])
                        .disabled(!session.canRequestSelectSubject)
                    Button("Mask's Black Areas") {
                        if session.prepareForOutsideDocumentAction(), let id = session.activeLayerID { session.loadMaskSelection(layerID: id) }
                    }
                        .disabled(session.activeLayer?.mask == nil || !session.canRequestSelectionEdit)
                    Divider()
                    Button("Expand…") { session.promptSelectionAmount(.expand) }
                        .disabled(!session.canRequestModifySelection)
                    Button("Contract…") { session.promptSelectionAmount(.contract) }
                        .disabled(!session.canRequestModifySelection)
                    Button("Feather…") { session.promptSelectionAmount(.feather) }
                        .disabled(!session.canRequestModifySelection)
                }
                CommandMenu("Image") {
                    Button("Curves…") { session.beginFilter(.curves) }
                        .configuredKeyboardShortcut("m").disabled(!session.canRequestColorAdjustment || session.hueSaturation != nil)
                    Button("Levels…") { session.beginLevels() }
                        .configuredKeyboardShortcut("l").disabled(!session.canRequestColorAdjustment || session.hueSaturation != nil)
                    Button("Hue/Saturation…") { session.beginHueSaturation() }
                        .configuredKeyboardShortcut("u").disabled(!session.canRequestColorAdjustment)
                    ForEach([FilterKind.blackWhite, .colorBalance, .exposure, .gradientMap, .grain], id: \.self) { kind in
                        Button("\(kind.rawValue)…") { session.beginFilter(kind) }
                            .disabled(!session.canRequestColorAdjustment || session.hueSaturation != nil)
                    }
                    Button(session.isMaskSelected ? "Invert Mask" : "Invert") { Task { await session.invertPixels() } }
                        .configuredKeyboardShortcut("i")
                        .disabled(!session.canRequestInvert)
                    Divider()
                    Button("Canvas Size…") { Task { await applicationDelegate.projects.canvasSize() } }
                        .configuredKeyboardShortcut("c", modifiers: [.command, .option])
                        .disabled(session.document == nil || !applicationDelegate.projects.canRequestStart)
                    Button("Image Size…") { Task { await applicationDelegate.projects.imageSize() } }
                        .configuredKeyboardShortcut("i", modifiers: [.command, .option])
                        .disabled(session.document == nil || !applicationDelegate.projects.canRequestStart)
                    Button("Trim…") { Task { await applicationDelegate.projects.trim() } }
                        .disabled(session.document == nil || !applicationDelegate.projects.canRequestStart)
                    Group {
                        Divider()
                        Button("Flip Canvas Horizontal") { session.flipCanvas(horizontally: true) }
                            .disabled(!session.canRequestLayerEdit)
                        Button("Flip Canvas Vertical") { session.flipCanvas(horizontally: false) }
                            .disabled(!session.canRequestLayerEdit)
                    }
                }
                CommandMenu("Filter") {
                    ForEach(FilterKind.allCases.filter { $0 != .contentAwareFill && !$0.isImageAdjustment }, id: \.self) { kind in
                        Button("\(kind.rawValue)…") { session.beginFilter(kind) }
                            .disabled(!(kind == .vignette ? session.canRequestVignette : session.canRequestColorAdjustment) || session.hueSaturation != nil)
                    }
                }
                CommandMenu("Layer") {
                    Menu("New Adjustment Layer") {
                        ForEach(AdjustmentKind.allCases, id: \.self) { kind in
                            Button(kind.rawValue + (kind.isEditable ? "…" : "")) {
                                if session.prepareForOutsideDocumentAction() { session.addAdjustment(kind) }
                            }
                        }
                    }.disabled(!session.canRequestLayerEdit || session.document == nil)
                    Button("Edit Adjustment…") {
                        if session.prepareForOutsideDocumentAction() { session.adjustmentEditingID = session.activeLayerID }
                    }.disabled(!session.canRequestLayerEdit || session.activeLayer?.adjustment == nil)
                    Divider()
                    Button(session.canRequestTransformSelection ? "Transform Selection" : "Transform Layer") { session.transformCommand() }
                        .configuredKeyboardShortcut("t").disabled(!session.canRequestTransform && !session.canRequestTransformSelection)
                    Button(session.selection == nil ? "Duplicate Layer" : "Layer via Copy") { if session.prepareForOutsideDocumentAction() { session.layerViaCopy() } }
                        .configuredKeyboardShortcut("j").disabled(!session.canRequestCopyPixels && !session.canRequestCopyLayer)
                    Divider()
                    Button(session.activeLayer?.maskSourceID == nil ? "Create Clipping Mask" : "Release Clipping Mask") {
                        if session.prepareForOutsideDocumentAction(), let id = session.activeLayerID { session.toggleClippingMask(id) }
                    }
                    .configuredKeyboardShortcut("g", modifiers: [.command, .option])
                    .disabled(session.activeLayerID.map { !session.canToggleClippingMask($0, ignoringText: true) } ?? true)
                    Divider()
                    Button("Group Selected Layers") { if session.prepareForOutsideDocumentAction() { session.groupSelectedLayers() } }
                        .configuredKeyboardShortcut("g").disabled(!session.canRequestLayerEdit)
                    Button("Move Out of Folder") { if session.prepareForOutsideDocumentAction() { session.moveActiveLayerOutOfGroup() } }
                        .disabled(!session.canRequestLayerEdit || session.activeLayer?.parentID == nil)
                    Button("New Blank Layer") { if session.prepareForOutsideDocumentAction() { session.addBlankLayer() } }
                        .configuredKeyboardShortcut("n", modifiers: [.command, .shift]).disabled(!session.canRequestLayerEdit)
                    Button("Rename Layer…") { if session.prepareForOutsideDocumentAction() { session.renamingLayerID = session.activeLayerID } }
                        .disabled(!session.canRequestLayerEdit || session.activeLayer == nil)
                    Button(session.activeLayer?.isVisible == false ? "Show Layer" : "Hide Layer") {
                        if session.prepareForOutsideDocumentAction(), let id = session.activeLayerID { session.toggleLayerVisibility(id) }
                    }.disabled(!session.canRequestLayerEdit || session.activeLayer == nil)
                    Divider()
                    Button("Move Layer Up") { if session.prepareForOutsideDocumentAction() { session.moveActiveLayer(by: 1) } }
                        .configuredKeyboardShortcut("]").disabled(!session.canRequestMoveActiveLayer(by: 1))
                    Button("Move Layer Down") { if session.prepareForOutsideDocumentAction() { session.moveActiveLayer(by: -1) } }
                        .configuredKeyboardShortcut("[").disabled(!session.canRequestMoveActiveLayer(by: -1))
                    Group {
                        Button(session.mergeTitle) { if session.prepareForOutsideDocumentAction() { session.mergeLayers() } }
                            .configuredKeyboardShortcut("e").disabled(!session.canRequestMergeLayers)
                        Divider()
                        Button("Flip Layer Horizontal") { if session.prepareForOutsideDocumentAction() { session.flipLayers(horizontally: true) } }
                            .disabled(!session.canRequestTransform)
                        Button("Flip Layer Vertical") { if session.prepareForOutsideDocumentAction() { session.flipLayers(horizontally: false) } }
                            .disabled(!session.canRequestTransform)
                    }
                    Divider()
                    Button(session.selectedEffect != nil ? "Delete " + session.selectedEffect!.kind.rawValue : session.isMaskSelected && session.activeLayer?.mask != nil ? "Delete Layer Mask" : session.selectedLayerIDs.count > 1 ? "Delete Layers" : "Delete Layer") {
                        if session.prepareForOutsideDocumentAction() { session.deleteLayerOrMask() }
                    }
                        .disabled(!session.canRequestLayerEdit || session.activeLayer == nil)
                }
            }
    }
}
