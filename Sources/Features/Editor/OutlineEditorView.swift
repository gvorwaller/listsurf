import SwiftUI
import Domain
import Platform
#if os(iOS)
import UIKit
#endif
#if DEBUG
import os
#endif

struct OutlineEditorView: View {
    @Bindable var store: ListStore
    @Binding var showInspector: Bool
    let notePreviewLineCount: Int
    @Environment(\.undoManager) private var undoManager
    // td-e7c609: reference types, not `@State String` — mutated per
    // keystroke only inside the field subviews' own bodies (RenameFieldView,
    // AddItemFieldView), so typing invalidates just the active field, not
    // the whole outline List. This view reads/clears `.text` only inside
    // its own imperative handlers (commit, cancel, iOS keyboard-accessory
    // Done/Cancel) — never inside `body`.
    @State private var renameDraft = EditorDraftText()
    @State private var addDraft = EditorDraftText()
    @State private var selectionFromAddFlow: Set<UUID> = []
    @FocusState private var focus: EditorFocus?
    // td-ff531e: when arming restructures the outline (⌘Return's .child
    // placement expands the parent row), FocusState reports the target as
    // focused while AppKit's first responder never moves — the bridge
    // silently does not run, no state-change event ever fires to reveal it,
    // and typing goes to the List. Proven by responder-chain event logging
    // (2026-07-19) after three pure-SwiftUI escalations were falsified.
    // While a target is pending (cleared by: first typed character, one
    // steal re-assert, or a deliberate dismissal such as the iOS ⌄ button),
    // the responder chain is verified after assignment and the NSTextField
    // is focused directly when the bridge didn't do it.
    @State private var pendingFocus: EditorFocus?
    #if os(iOS)
    // td-1ef423: List's automatic keyboard-avoidance safe-area inset does
    // NOT apply in this hierarchy — measured on-device (screenshot
    // evidence): with the add/rename keyboard accessory toolbar visible,
    // the List still laid out its content all the way to the physical
    // screen bottom, so `ScrollViewReader.scrollTo(anchor: .bottom)` was
    // landing the target row exactly where the toolbar/keyboard covers it.
    // Likely cause: the pre-existing `.safeAreaInset(edge: .bottom) {
    // selectedItemActionBar }` on this same view redefines the bottom
    // safe area for its subtree, and the keyboard toolbar's own automatic
    // contribution doesn't compose with that. Tracking the real keyboard
    // frame and reserving it explicitly is the fix that doesn't depend on
    // that automatic (and here, non-functional) propagation.
    @State private var keyboardOverlap: CGFloat = 0
    /// Simulator-UI-test-runner-only floor, covering a standard iPhone
    /// keyboard (~271-346pt) plus the accessory toolbar (~44-50pt).
    /// `keyboardWillChangeFrameNotification`'s reported frame was
    /// empirically unreliable ONLY there (the software keyboard never
    /// visually presents in that runner even though the accessory toolbar
    /// still docks to the screen bottom, per gate-review finding on
    /// 1cf3301). On a real device the notification reports correctly,
    /// including the two cases where the keyboard is legitimately absent
    /// (chevron-dismissed, hardware keyboard attached) — applying this
    /// floor there would wrongly reserve blank space in both. Gated on
    /// `isRunningUITests` so production never sees it.
    private static let minimumKeyboardClearance: CGFloat = 350
    /// Same UI-test-mode signal `ListsurfApp.init()` uses to pick an
    /// isolated persistence store (`LISTSURF_UI_TEST_STORE` launch
    /// environment) — reused here as the gate for the Simulator-runner-only
    /// keyboard-clearance floor above, rather than inventing a second flag.
    private static var isRunningUITests: Bool {
        ProcessInfo.processInfo.environment["LISTSURF_UI_TEST_STORE"] != nil
    }
    #endif

    var body: some View {
        #if os(iOS)
        editorContent
            .safeAreaInset(edge: .bottom, spacing: 0) {
                selectedItemActionBar
            }
            .modifier(KeyboardAccessoryModifier(
                isVisible: store.isTextInputActive,
                onCancel: cancelTextEntry,
                onDone: commitTextEntry,
                // Below/Child commit the current draft first (as Help
                // documents), then continue relative to the fresh selection —
                // never silently relocate typed text to another placement.
                onAddBelow: {
                    commitTextEntry()
                    selectedRow.map { store.beginAdding(.below($0.id)) }
                },
                onAddChild: {
                    commitTextEntry()
                    selectedRow.map { store.beginAdding(.child($0.id)) }
                },
                onIndent: { selectedRow.map { store.indent(itemID: $0.id, undoManager: undoManager) } },
                onOutdent: { selectedRow.map { store.outdent(itemID: $0.id, undoManager: undoManager) } },
                onDismissKeyboard: { pendingFocus = nil; focus = nil },
                hasSelectedItem: selectedRow != nil
            ))
        #else
        // macOS keyboard ownership: the List (via native selection) handles
        // ↑/↓/⌘-click/⇧-click itself. The editor owns Return = add below
        // (root-add with no selection), ⇧Return = add above + rename,
        // ⌘Return = add child, Tab/⇧Tab = indent/outdent, and Space =
        // toggle check. The bare keys must never be menu equivalents, which
        // would intercept typing in every text field in the window; the add
        // keys are editor-owned so arming never depends on menu dispatch
        // (the FocusState→AppKit hand-off is unreliable there — td-ff531e).
        editorContent
            .onKeyPress(.return, phases: .down) { keyPress in
                handleReturnKey(modifiers: keyPress.modifiers)
            }
            .onKeyPress(.space, phases: .down) { keyPress in
                handleSpaceKey(modifiers: keyPress.modifiers)
            }
            // Escape fallback: the add/rename fields own Escape while they
            // have focus, but focus assignment is task-deferred (Phase 1) —
            // an Escape landing in the deferral window used to vanish,
            // leaving the add flow armed and every menu command disabled
            // (Gate M1 diagnostic, 2026-07-14). This editor-level handler
            // catches what the fields don't.
            .onKeyPress(.escape, phases: .down) { _ in
                if store.addPlacement != nil {
                    cancelAdding()
                    CommandInvocation.post(CommandCatalog.escape)
                    return .handled
                }
                if store.editingItemID != nil {
                    cancelEdit()
                    CommandInvocation.post(CommandCatalog.escape)
                    return .handled
                }
                if !store.selectedItemIDs.isEmpty {
                    store.selectedItemIDs = []
                    CommandInvocation.post(CommandCatalog.escape)
                    return .handled
                }
                // td-c85e4b (Gate M3): with nothing left to back out of,
                // this used to return `.ignored` and let AppKit's responder
                // chain carry the Esc up to the sidebar (spec says a second
                // Esc does nothing). Consuming it here is a deliberate
                // tradeoff: Esc can no longer exit full-screen while the
                // editor is focused with an empty selection. Accepted per
                // the M5 gate fix plan (item 7) — the editor owning Esc end
                // to end beats the escape reaching the sidebar unannounced.
                return .handled
            }
            // ⇧Tab arrives as a DIFFERENT key (backtab, U+0019) on macOS —
            // `.onKeyPress(.tab)` never fires for it, so focus traversal used
            // to win and dump the user in the sidebar search field (Gate M1
            // finding, 2026-07-14). Match both keys explicitly.
            .onKeyPress(phases: .down) { keyPress in
                let isBacktab = keyPress.characters == "\u{19}"
                guard keyPress.key == .tab || isBacktab else { return .ignored }
                return handleTabKey(isShiftPressed: isBacktab || keyPress.modifiers.contains(.shift))
            }
        #endif
    }

    private var editorContent: some View {
        Group {
            if store.filteredRows.isEmpty && store.addPlacement == nil && store.searchText.isEmpty {
                filteredEmptyState
            } else if store.filteredRows.isEmpty && store.addPlacement == nil {
                ContentUnavailableView.search(text: store.searchText)
            } else {
                outlineList
            }
        }
        .outlineSearch(text: $store.searchText)
        .onAppear {
            // If this view was recreated while a rename was already active
            // (the onChange below won't fire for an unchanged value), seed
            // the draft buffer from the item.
            if let editingID = store.editingItemID,
               let item = store.items.first(where: { $0.id == editingID }) {
                renameDraft.text = item.title
            }
        }
        .onChange(of: store.editingItemID) { oldValue, newValue in
            if let newValue, let item = store.items.first(where: { $0.id == newValue }) {
                renameDraft.text = item.title
                // Task-deferred: the assignment must land after the rename
                // field mounts (one runloop hop), not inside the transaction
                // that flips editingItemID (spec §2, B2/B4 fix).
                assignFocus(.rename(newValue))
            } else if let oldValue, newValue == nil {
                if pendingFocus == .rename(oldValue) { pendingFocus = nil }
                // Editing was ended by something other than this view's own
                // commit/cancel (both consume the draft first) — e.g. the
                // store enforcing add/rename exclusivity. Commit the
                // stranded draft rather than silently discarding it.
                let text = renameDraft.text.trimmingCharacters(in: .whitespaces)
                renameDraft.text = ""
                if !text.isEmpty {
                    store.updateItemTitle(id: oldValue, title: text, undoManager: undoManager)
                }
            }
        }
        .onChange(of: store.addPlacement) { _, newValue in
            // Task-deferred for the same reason as above: nil→value always
            // fires (cancelAdding/dismissPendingAdd nil the placement before
            // any re-add), and the continuation flow's .below(a)→.below(b)
            // is a value change that also fires.
            if newValue != nil {
                assignFocus(.addField)
            } else if pendingFocus == .addField {
                pendingFocus = nil
            }
        }
        .onChange(of: focus) { _, newValue in
            // One-shot re-assert (B2 escalation, revised after
            // testCommandReturnArmsEditableChildField falsified the
            // clear-on-reach version): the menu-equivalent churn steals focus
            // AFTER it lands, so the guard must survive the reach and fire on
            // the first loss. It is consumed by that one re-assert; deliberate
            // dismissals (iOS ⌄, Esc, placement end) clear it explicitly, and
            // the first typed character clears it as focus-proven.
            guard let pending = pendingFocus, newValue != pending else { return }
            pendingFocus = nil
            focus = pending
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            // Menu-equivalent invocations can swallow the FocusState
            // assignment entirely while the menu session is active — then no
            // focus change ever fires and the steal-detect above never runs.
            // The menu system announcing its own end is the deterministic
            // moment the field can actually take focus.
            guard let pending = pendingFocus else { return }
            pendingFocus = nil
            Task { @MainActor in focus = pending }
        }
        #endif
        .onChange(of: store.selectedItemIDs) { _, newValue in
            // Click-away commits an in-progress rename, Finder-style.
            if let editingID = store.editingItemID, !newValue.contains(editingID) {
                commitEdit(editingID)
            }
            // Any selection change — including deselecting by clicking empty
            // space — dismisses a pending add, except when the change is the
            // add flow itself selecting the item it just created.
            if store.addPlacement != nil, newValue != selectionFromAddFlow {
                dismissPendingAdd()
            }
        }
    }

    /// Filter-aware replacement for the mode-switch (spec §1.4): with items
    /// on the list but none visible under the active filter, the empty state
    /// explains why and offers a way back to All rather than looking like an
    /// empty list.
    @ViewBuilder
    private var filteredEmptyState: some View {
        if store.checkFilter == .remaining, !store.items.isEmpty {
            allDoneState
        } else if store.checkFilter == .completed, !store.items.isEmpty {
            noCompletedState
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Items", systemImage: "text.badge.plus")
        } description: {
            Text("Add your first item to start building this list.")
        } actions: {
            Button("Add Item") {
                store.beginAdding(.root)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("editor.addFirstItem")
        }
    }

    /// Carried from `CheckModeView.swift:46-58` (M5 unification).
    private var allDoneState: some View {
        let p = store.progress
        return ContentUnavailableView {
            Label("All Done!", systemImage: "checkmark.circle.fill")
        } description: {
            Text("\(p.checked)/\(p.total) items checked")
        } actions: {
            Button("Show All") {
                store.checkFilter = .all
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var noCompletedState: some View {
        ContentUnavailableView {
            Label("No Completed Items", systemImage: "circle")
        } actions: {
            Button("Show All") {
                store.checkFilter = .all
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var outlineList: some View {
        #if os(iOS)
        // td-1ef423: the List's default keyboard avoidance doesn't reach a
        // freshly-armed add field or rename field reliably (Gate I3/I1b) —
        // a ScrollViewReader lets us drive scrollTo explicitly once the
        // keyboard/field has actually appeared. macOS has no software
        // keyboard, so this whole wrapper is iOS-only; the plain `List`
        // below is byte-for-byte what macOS renders.
        ScrollViewReader { proxy in
            outlineListContent
                // td-1ef423: reserve the real keyboard/accessory height as
                // extra bottom clearance on the List itself — see the
                // `keyboardOverlap` doc comment for why this can't be left
                // to automatic keyboard-avoidance here. Without this,
                // `scrollTo(anchor: .bottom)` positions the row against the
                // List's own (unshrunk) bottom edge, which is exactly where
                // the keyboard/toolbar covers it.
                //
                // Gate-review finding on 1cf3301: the `minimumKeyboardClearance`
                // floor must NOT apply in production — `isTextInputActive`
                // stays true in two real, gate-verified situations where
                // the keyboard is legitimately NOT on screen (chevron
                // keyboard-dismiss with the add flow still armed; a
                // hardware keyboard attached), and `keyboardOverlap`
                // correctly reports ~0 in both. Forcing a 350pt floor there
                // regressed layout with a permanent blank dead zone. The
                // floor is scoped to exactly the one environment where it's
                // needed: the Simulator UI-test runner.
                .safeAreaPadding(
                    .bottom,
                    store.isTextInputActive
                        ? (Self.isRunningUITests ? max(keyboardOverlap, Self.minimumKeyboardClearance) : keyboardOverlap)
                        : 0
                )
                .onChange(of: store.addPlacement) { _, newValue in
                    guard newValue != nil else { return }
                    scrollToActiveField(proxy)
                }
                .onChange(of: store.editingItemID) { _, newValue in
                    guard newValue != nil else { return }
                    scrollToActiveField(proxy)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                    updateKeyboardOverlap(note)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                    // Re-assert: the keyboard's final height isn't known at
                    // the moment addPlacement/editingItemID flips, so the
                    // first scrollTo above can undershoot. keyboardDidShow
                    // fires once the keyboard has actually finished
                    // presenting, giving a second, better-informed attempt.
                    guard store.isTextInputActive else { return }
                    scrollToActiveField(proxy)
                }
        }
        #else
        outlineListContent
        #endif
    }

    private var outlineListContent: some View {
        List(selection: $store.selectedItemIDs) {
            ForEach(store.filteredRows) { row in
                outlineRow(row)
                    // D5/D9/B6: the move trait MUST be applied here, on the
                    // ForEach's direct content — a `.moveDisabled` inside
                    // OutlineRowView (a nested child) is silently ignored by
                    // List (proven at Gate M1: multi-drags lifted). Hover
                    // gating is retired — see RowMoveDisabled's doc comment.
                    .modifier(RowMoveDisabled(blocked: dragBlocked(row)))
                    .tag(row.id)
                    .listRowInsets(EdgeInsets(
                        top: 4,
                        leading: 16 + Double(row.depth) * 20,
                        bottom: 4,
                        trailing: 16
                    ))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            store.pendingDeletionIDs = [row.id]
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }

                if let addFieldDepth = addFieldPlacement(after: row) {
                    addItemField(depth: addFieldDepth)
                }
            }
            .onMove { source, destination in
                store.moveRows(from: source, to: destination, undoManager: undoManager)
            }

            if shouldShowRootAddField {
                addItemField(depth: 0)
            }
        }
        .listStyle(.sidebar)
        // td-e7c609: `store.rowsVersion` is an Int bumped only when
        // `filteredRows`' composition can actually change (rebuild, filter,
        // search) — animating on it avoids remapping the filtered array to
        // `[UUID]` (and recomputing the filter itself) on every body pass.
        .animation(.default, value: store.rowsVersion)
        .modifier(OutlineContextMenuModifier(
            store: store,
            onShowDetails: showDetails(itemID:)
        ))
    }

    #if os(iOS)
    /// td-1ef423: reads live store state rather than the `onChange` payload
    /// so all three triggers (add armed, rename armed, keyboard re-assert)
    /// share one implementation — add and rename are mutually exclusive
    /// (see `dismissPendingAdd`/`onChange(of: store.selectedItemIDs)`), so
    /// exactly one branch below is ever live at a time.
    ///
    /// The real fix for landing ABOVE the keyboard is the
    /// `keyboardOverlap`/`safeAreaPadding` in `outlineList` above — that
    /// gives `anchor: .bottom` a List frame that actually excludes the
    /// keyboard. This retry loop covers a separate, softer timing issue:
    /// `keyboardOverlap` itself updates asynchronously off a notification,
    /// so the very first scrollTo attempt (250ms after arming) can still
    /// fire before that value has caught up to a keyboard that's still
    /// animating in. Retrying a few times over ~1s re-scrolls once it has.
    private func scrollToActiveField(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            for delayMS in [250, 150, 150, 150, 150] {
                try? await Task.sleep(for: .milliseconds(delayMS))
                if store.addPlacement != nil {
                    proxy.scrollTo(EditorScrollAnchor.addField, anchor: .bottom)
                } else if let editingItemID = store.editingItemID {
                    proxy.scrollTo(editingItemID, anchor: .center)
                } else {
                    return
                }
            }
        }
    }

    /// td-1ef423: derives how much of the screen's bottom the keyboard (plus
    /// its `.toolbar(placement: .keyboard)` accessory, which reports as part
    /// of the same frame) currently occupies, from the one notification
    /// UIKit posts for every keyboard frame change — show, hide, and height
    /// changes (e.g. rotation, QuickType bar, a hardware-keyboard toggle).
    /// `frame.origin.y` is in screen coordinates, so `screenHeight -
    /// origin.y` is exactly the overlap; clamped to 0 for a fully-dismissed
    /// keyboard, where `origin.y` lands at or past the screen's bottom edge.
    private func updateKeyboardOverlap(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let screenHeight = UIScreen.main.bounds.height
        keyboardOverlap = max(0, screenHeight - frame.origin.y)
    }
    #endif

    /// B6 fix (spec §2): the drag gate terms, all editor-computed so trait
    /// changes re-diff correctly (Rev 2.4). Phase 2 adds the filter term
    /// (`checkFilter != .all`): filtered rows are a non-contiguous excerpt
    /// of true sibling order, same rationale as the search guard.
    private func dragBlocked(_ row: FlatRow) -> Bool {
        if store.isTextInputActive || !store.searchText.isEmpty { return true }
        if store.checkFilter != .all { return true }
        if rowInMultiSelection(row) { return true }
        return false
    }

    private func rowInMultiSelection(_ row: FlatRow) -> Bool {
        store.selectedItemIDs.count > 1 && store.selectedItemIDs.contains(row.id)
    }

    private func outlineRow(_ row: FlatRow) -> some View {
        HStack(spacing: 8) {
            OutlineRowView(
                row: row,
                isEditing: store.editingItemID == row.id,
                notePreviewLineCount: notePreviewLineCount,
                renameDraft: renameDraft,
                focus: $focus,
                onToggleExpand: { store.toggleExpanded(row.id) },
                onToggleCheck: {
                    store.toggleCheck(itemID: row.id, undoManager: undoManager)
                    Haptics.checkToggle()
                },
                onCommitEdit: { commitEdit(row.id) },
                onCancelEdit: {
                    cancelEdit()
                    CommandInvocation.post(CommandCatalog.escape)
                }
            )

            Menu {
                // Hints off: this menu targets the row, while the displayed
                // shortcuts act on the selection — they may differ.
                ItemActionsMenu(
                    store: store,
                    itemIDs: [row.id],
                    showsShortcutHints: false,
                    selectsTargetOnAct: true,
                    onShowDetails: showDetails(itemID:)
                )
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Actions for \(row.item.title)")
            .accessibilityIdentifier("editor.rowActions")

            Button(role: .destructive) {
                store.pendingDeletionIDs = [row.id]
            } label: {
                Image(systemName: "trash")
                    .imageScale(.large)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete \(row.item.title)")
            .accessibilityIdentifier("editor.deleteItem")
        }
        .contentShape(Rectangle())
        .modifier(RowSelectionTapModifier(
            rowID: row.id,
            onSelect: selectRow(_:),
            onDoubleTap: showDetails(itemID:)
        ))
    }

    #if os(iOS)
    @ViewBuilder
    private var selectedItemActionBar: some View {
        if let row = selectedRow, store.addPlacement == nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button {
                        store.beginAdding(.below(row.id))
                    } label: {
                        Label("Below", systemImage: "plus")
                    }
                    .accessibilityIdentifier("editor.ios.addBelow")

                    Button {
                        store.beginAdding(.child(row.id))
                    } label: {
                        Label("Child", systemImage: "arrow.turn.down.right")
                    }
                    .accessibilityIdentifier("editor.ios.addChild")

                    Button {
                        store.indent(itemID: row.id, undoManager: undoManager)
                    } label: {
                        Label("Indent", systemImage: "increase.indent")
                    }
                    .accessibilityIdentifier("editor.ios.indent")

                    Button {
                        store.outdent(itemID: row.id, undoManager: undoManager)
                    } label: {
                        Label("Outdent", systemImage: "decrease.indent")
                    }
                    .accessibilityIdentifier("editor.ios.outdent")

                    Button {
                        store.moveUp(itemID: row.id, undoManager: undoManager)
                    } label: {
                        Label("Up", systemImage: "arrow.up")
                    }
                    .accessibilityIdentifier("editor.ios.moveUp")

                    Button {
                        store.moveDown(itemID: row.id, undoManager: undoManager)
                    } label: {
                        Label("Down", systemImage: "arrow.down")
                    }
                    .accessibilityIdentifier("editor.ios.moveDown")

                    Button {
                        showDetails(itemID: row.id)
                    } label: {
                        Label("Details", systemImage: "info.circle")
                    }
                    .accessibilityIdentifier("editor.ios.details")

                    Button(role: .destructive) {
                        store.pendingDeletionIDs = [row.id]
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .accessibilityIdentifier("editor.ios.delete")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("editor.ios.actionBar")
            // td-03f6d1(d) / Gate I4: no repro, defensive only. A residual
            // keyboard-avoidance offset left over from the add/rename flow
            // could otherwise float this bar mid-screen instead of pinning
            // it to the bottom safe area.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            #if DEBUG
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                let screenHeight = UIScreen.main.bounds.height
                let offset = screenHeight - frame.maxY
                guard offset > 100 else { return }
                Self.actionBarLogger.error(
                    "selectedItemActionBar floating: frame=\(frame.debugDescription, privacy: .public) screenBounds=\(UIScreen.main.bounds.debugDescription, privacy: .public) offsetFromBottom=\(offset, privacy: .public)"
                )
            }
            #endif
        }
    }
    #endif

    #if DEBUG
    private static let actionBarLogger = Logger(subsystem: "net.vorwaller.listsurf", category: "ui")
    #endif

    private func addItemField(depth: Int) -> some View {
        AddItemFieldView(
            placeholder: addPlaceholder,
            depth: depth,
            draft: addDraft,
            focus: $focus,
            onAppearCheckFocus: checkAddFieldFocusEscalation,
            onCommit: commitNewItem,
            onCancel: {
                cancelAdding()
                CommandInvocation.post(CommandCatalog.escape)
            },
            onFirstKeystroke: {
                // First typed character proves focus landed — stop
                // guarding, so a later deliberate focus move (sidebar
                // search, ⌥⌘I) isn't rebuffed.
                if pendingFocus == .addField { pendingFocus = nil }
            }
        )
        #if os(iOS)
        .background(
            // td-1ef423: a SEPARATE, non-interactive marker carries the
            // scrollTo identity. Applying `.id()` directly to the add field
            // itself regressed testAddFieldPlacementAndKeyboardDismissal —
            // with an explicit `.id()` on the focused row, SwiftUI/UIKit
            // tore down and rebuilt its backing text-field view on List
            // body recomputes that had nothing to do with the add field
            // (e.g. every keystroke committed elsewhere), dropping first
            // responder. This untouched, unfocusable sibling gives
            // scrollTo the same on-screen position without ever touching
            // the focused field's own identity.
            Color.clear
                .id(EditorScrollAnchor.addField)
                .accessibilityHidden(true)
        )
        #endif
    }

    #if os(macOS)
    private func checkAddFieldFocusEscalation() {
        // td-ff531e: when arming restructures the outline (.child expands
        // the parent), the field mounts AFTER every deferred assignment
        // already ran — FocusState holds .addField but no live view ever
        // claimed it, so the List keeps first responder and typing goes
        // nowhere. The field itself is the only place guaranteed to exist
        // after registration: cycle the binding from here.
        if pendingFocus == .addField, !Self.textEditorIsFirstResponder() {
            Task { @MainActor in
                await Task.yield()
                guard pendingFocus == .addField, !Self.textEditorIsFirstResponder() else { return }
                Self.focusAddFieldDirectly()
            }
        }
    }
    #else
    private func checkAddFieldFocusEscalation() {}
    #endif

    private func addFieldPlacement(after row: FlatRow) -> Int? {
        switch store.addPlacement {
        case nil, .root:
            return nil
        case .below(let itemID):
            return row.id == itemID ? row.depth : nil
        case .child(let itemID):
            return row.id == itemID ? row.depth + 1 : nil
        }
    }

    /// The add field must always be reachable while adding is active. If its
    /// anchor row is hidden (search filter, collapsed ancestor), fall back to
    /// the root slot rather than leaving an active entry with no field.
    private var shouldShowRootAddField: Bool {
        switch store.addPlacement {
        case nil:
            return false
        case .root:
            return true
        case .below(let itemID), .child(let itemID):
            return !store.filteredRows.contains { $0.id == itemID }
        }
    }

    private func cancelAdding() {
        store.cancelAdding()
        addDraft.text = ""
    }

    private func cancelEdit() {
        renameDraft.text = ""
        store.cancelEditing()
    }

    private func commitEdit(_ id: UUID) {
        let text = renameDraft.text.trimmingCharacters(in: .whitespaces)
        renameDraft.text = ""
        store.cancelEditing()
        guard !text.isEmpty else { return }
        store.updateItemTitle(id: id, title: text, undoManager: undoManager)
    }

    private func commitNewItem() {
        guard let placement = store.addPlacement else { return }
        let text = addDraft.text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            cancelAdding()
            return
        }
        let newID = insertPendingItem(text, at: placement)
        // Keep the flow going: the next entry lands below the item just added.
        selectionFromAddFlow = [newID]
        store.beginAdding(.below(newID))
        addDraft.text = ""
    }

    /// Dismiss the add flow on click-away: commit typed text as a final
    /// item, or cancel an empty field — never leave a dangling entry field.
    private func dismissPendingAdd() {
        guard let placement = store.addPlacement else { return }
        let text = addDraft.text.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty {
            _ = insertPendingItem(text, at: placement)
        }
        cancelAdding()
    }

    private func insertPendingItem(_ text: String, at placement: OutlineAddPlacement) -> UUID {
        switch placement {
        case .root:
            store.addItem(title: text, undoManager: undoManager)
        case .below(let itemID):
            store.addItem(title: text, afterItemID: itemID, undoManager: undoManager)
        case .child(let itemID):
            store.addChild(parentID: itemID, title: text, undoManager: undoManager)
        }
    }

    /// A user tap always dismisses a pending add (commit-or-cancel), even if
    /// the tapped row is the item the add flow just created — the intent is
    /// "done entering, work with this row".
    /// Deferred focus assignment with the spec §2 B2 bounded escalation:
    /// one runloop hop, then a single yield-retry while the target is still
    /// pending. The one-shot `.onChange(of: focus)` re-assert covers the
    /// menu-dismissal race that lands after both.
    private func assignFocus(_ target: EditorFocus) {
        pendingFocus = target
        Task { @MainActor in
            focus = target
            await Task.yield()
            if pendingFocus == target, focus != target {
                focus = target
                return
            }
            #if os(macOS)
            // td-ff531e root cause (evidence: focus-debug log 2026-07-19):
            // on the menu-equivalent path, FocusState reports the target as
            // focused while AppKit's first responder never moved — the
            // makeFirstResponder bridge fails silently inside menu dispatch,
            // and no FocusState change ever fires to reveal it. The responder
            // chain is the ground truth: if no field editor is active, cycle
            // focus nil→target once (the steal-detect onChange re-asserts,
            // making the cycle self-completing and bounded by pendingFocus).
            if pendingFocus == target, focus == target, !Self.textEditorIsFirstResponder() {
                Self.focusAddFieldDirectly()
            }
            #endif
        }
    }

    #if os(macOS)
    private static func textEditorIsFirstResponder() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }

    private static func firstResponderDescription() -> String {
        guard let responder = NSApp.keyWindow?.firstResponder else { return "nil" }
        return String(describing: type(of: responder))
    }

    /// td-ff531e last-resort: SwiftUI's FocusState→responder bridge provably
    /// does not run when the add field mounts during an outline restructure
    /// (.child arming expands the parent) — state reads .addField, the field
    /// is mounted, the chain is clean, and no makeFirstResponder ever
    /// happens (focus-debug log, 2026-07-19). Focus the NSTextField itself.
    private static func focusAddFieldDirectly() {
        guard let window = NSApp.keyWindow, let content = window.contentView else { return }
        if let field = findAddTextField(in: content) {
            window.makeFirstResponder(field)
        }
    }

    private static func findAddTextField(in view: NSView) -> NSTextField? {
        // The SwiftUI accessibilityIdentifier does not propagate to the
        // backing AppKitTextField, so match on what does: an editable
        // NSTextField whose placeholder is one of the add field's. Add and
        // rename are mutually exclusive, the sidebar search lives in the
        // toolbar (outside contentView), and the inspector notes editor is
        // an NSTextView — a placeholder match is therefore unambiguous.
        // Must mirror `addPlaceholder` above.
        let addPlaceholders: Set<String> = ["New item", "New item below", "New child item"]
        var match: NSTextField?
        func walk(_ v: NSView) {
            if match != nil { return }
            if let field = v as? NSTextField, field.isEditable,
               let placeholder = field.placeholderString,
               addPlaceholders.contains(placeholder) {
                match = field
                return
            }
            v.subviews.forEach(walk)
        }
        walk(view)
        return match
    }
    #endif

    private func selectRow(_ id: UUID) {
        if store.addPlacement != nil {
            dismissPendingAdd()
        }
        store.selectedItemIDs = [id]
    }

    private func showDetails(itemID: UUID) {
        store.selectedItemIDs = [itemID]
        showInspector = true
    }

    #if os(macOS)
    private func handleReturnKey(modifiers: EventModifiers) -> KeyPress.Result {
        guard store.editingItemID == nil, store.addPlacement == nil else { return .ignored }
        if modifiers == .command {
            // ⌘Return = Add Child, handled here when the key reaches the
            // editor. The menu bar registers the same equivalent; whichever
            // layer wins arms the identical placement, so both routes are
            // correct — this handler guarantees the direct path exists.
            guard let row = selectedRow else { return .ignored }
            store.beginAdding(.child(row.id))
            CommandInvocation.post(CommandCatalog.addChild)
            return .handled
        }
        if modifiers == .shift {
            guard let row = selectedRow else { return .ignored }
            let newID = store.insertAbove(referenceID: row.id, title: "New Item", undoManager: undoManager)
            store.beginEditing(itemID: newID)
            CommandInvocation.post(CommandCatalog.addAbove)
            return .handled
        }
        guard modifiers.isEmpty else { return .ignored }
        if let row = selectedRow {
            store.beginAdding(.below(row.id))
        } else if store.selectedItemIDs.isEmpty {
            store.beginAdding(.root)
        } else {
            return .ignored
        }
        CommandInvocation.post(CommandCatalog.newItem)
        return .handled
    }

    private func handleTabKey(isShiftPressed: Bool) -> KeyPress.Result {
        guard store.editingItemID == nil, store.addPlacement == nil,
              !store.selectedItemIDs.isEmpty else {
            return .ignored
        }
        if isShiftPressed {
            store.outdent(itemIDs: store.selectedItemIDs, undoManager: undoManager)
            CommandInvocation.post(CommandCatalog.outdent)
        } else {
            store.indent(itemIDs: store.selectedItemIDs, undoManager: undoManager)
            CommandInvocation.post(CommandCatalog.indent)
        }
        return .handled
    }

    private func handleSpaceKey(modifiers: EventModifiers) -> KeyPress.Result {
        guard modifiers.isEmpty,
              !store.isTextInputActive,
              !store.selectedItemIDs.isEmpty else {
            return .ignored
        }
        store.toggleChecked(ids: store.selectedItemIDs, undoManager: undoManager)
        CommandInvocation.post(CommandCatalog.toggleChecked)
        return .handled
    }
    #endif

    private var selectedRow: FlatRow? {
        guard store.selectedItemIDs.count == 1,
              let selectedID = store.selectedItemIDs.first else {
            return nil
        }
        return store.flatRows.first { $0.id == selectedID }
    }

    private var addPlaceholder: String {
        switch store.addPlacement {
        case nil, .root:
            "New item"
        case .below:
            "New item below"
        case .child:
            "New child item"
        }
    }

    private func cancelTextEntry() {
        if store.addPlacement != nil {
            cancelAdding()
        }
        if store.editingItemID != nil {
            cancelEdit()
        }
    }

    private func commitTextEntry() {
        if let editingItemID = store.editingItemID {
            commitEdit(editingItemID)
        } else if store.addPlacement != nil {
            commitNewItem()
        }
    }
}

/// Selection-driven context menu. On macOS the double-click primary action
/// starts a rename, Finder-style. Shortcut hints are on: this menu's target
/// IS the selection, so the hints tell the truth.
private struct OutlineContextMenuModifier: ViewModifier {
    @Bindable var store: ListStore
    let onShowDetails: (UUID) -> Void
    @Environment(\.undoManager) private var undoManager

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .contextMenu(forSelectionType: UUID.self) { ids in
                menuContent(ids)
            } primaryAction: { ids in
                if ids.count == 1, let id = ids.first {
                    store.beginEditing(itemID: id)
                }
            }
        #else
        content
            .contextMenu(forSelectionType: UUID.self) { ids in
                menuContent(ids)
            }
        #endif
    }

    @ViewBuilder
    private func menuContent(_ ids: Set<UUID>) -> some View {
        if ids.isEmpty {
            Button {
                store.beginAdding(.root)
            } label: {
                Label(CommandCatalog.newItem.title, systemImage: CommandCatalog.newItem.systemImage)
            }
            Divider()
            Button(CommandCatalog.expandAll.title) { store.expandAll() }
            Button(CommandCatalog.collapseAll.title) { store.collapseAll() }
        } else {
            ItemActionsMenu(
                store: store,
                itemIDs: ids,
                showsShortcutHints: true,
                selectsTargetOnAct: false,
                onShowDetails: onShowDetails
            )
        }
    }
}

/// iOS selects by row tap (List selection outside edit mode is a macOS
/// affordance); macOS relies on native List selection and adds nothing.
///
/// Double-tap opens Details (Rev 2.5, spec §1.6, td-ee5174). The double-tap
/// gesture is attached with `.simultaneousGesture` rather than a second
/// `.onTapGesture(count: 2)` — two competing `.gesture` recognizers of
/// different counts force SwiftUI to wait for the higher count to fail
/// before firing the lower one, delaying every single tap. Simultaneous
/// gestures recognize independently: the single-tap handler still fires the
/// instant one tap completes, and a fast second tap additionally fires the
/// double-tap handler.
private struct RowSelectionTapModifier: ViewModifier {
    let rowID: UUID
    let onSelect: (UUID) -> Void
    let onDoubleTap: (UUID) -> Void

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .onTapGesture {
                onSelect(rowID)
            }
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    onDoubleTap(rowID)
                }
            )
        #else
        content
        #endif
    }
}

private struct KeyboardAccessoryModifier: ViewModifier {
    let isVisible: Bool
    let onCancel: () -> Void
    let onDone: () -> Void
    let onAddBelow: () -> Void
    let onAddChild: () -> Void
    let onIndent: () -> Void
    let onOutdent: () -> Void
    let onDismissKeyboard: () -> Void
    let hasSelectedItem: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if isVisible {
                        Button("Cancel", action: onCancel)
                            .accessibilityIdentifier("editor.keyboard.cancel")

                        Spacer()

                        Button("Below", action: onAddBelow)
                            .disabled(!hasSelectedItem)
                            .accessibilityIdentifier("editor.keyboard.addBelow")

                        Button("Child", action: onAddChild)
                            .disabled(!hasSelectedItem)
                            .accessibilityIdentifier("editor.keyboard.addChild")

                        Button {
                            onIndent()
                        } label: {
                            Image(systemName: "increase.indent")
                        }
                        .disabled(!hasSelectedItem)
                        .accessibilityIdentifier("editor.keyboard.indent")

                        Button {
                            onOutdent()
                        } label: {
                            Image(systemName: "decrease.indent")
                        }
                        .disabled(!hasSelectedItem)
                        .accessibilityIdentifier("editor.keyboard.outdent")

                        Button(action: onDismissKeyboard) {
                            Image(systemName: "keyboard.chevron.compact.down")
                        }
                        .accessibilityLabel("Dismiss Keyboard")
                        .accessibilityIdentifier("editor.keyboard.dismiss")

                        Button("Done", action: onDone)
                            .bold()
                            .accessibilityIdentifier("editor.keyboard.done")
                    }
                }
            }
        #else
        content
        #endif
    }
}

#if os(iOS)
/// td-1ef423: `ScrollViewReader.scrollTo` identity for the add field. A
/// dedicated enum rather than a sentinel UUID/string — it can never
/// alias an item's `UUID` no matter what value that happens to take.
private enum EditorScrollAnchor: Hashable {
    case addField
}
#endif

/// Add-item field, extracted from `OutlineEditorView.addItemField` (td-e7c609):
/// a small dedicated leaf view whose OWN body reads/writes `draft.text`, so
/// per-keystroke SwiftUI invalidation stops here rather than propagating up
/// through the outline `List`. `OutlineEditorView` keeps the full commit
/// contract (insert, re-arm the continuation placement, the stranded-draft
/// fallback on external session end) and the td-ff531e focus escalation;
/// this view forwards session-end signals (submit/escape) and a one-shot
/// first-keystroke signal that clears the pending-focus guard.
private struct AddItemFieldView: View {
    let placeholder: String
    let depth: Int
    @Bindable var draft: EditorDraftText
    let focus: FocusState<EditorFocus?>.Binding
    let onAppearCheckFocus: () -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void
    let onFirstKeystroke: () -> Void

    @State private var firstKeystrokeSignaled = false

    var body: some View {
        HStack {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.green)
            TextField(placeholder, text: $draft.text)
                .accessibilityIdentifier("editor.newItem")
                .focused(focus, equals: .addField)
                .onAppear(perform: onAppearCheckFocus)
                .onChange(of: draft.text) { _, newValue in
                    guard !firstKeystrokeSignaled, !newValue.isEmpty else { return }
                    firstKeystrokeSignaled = true
                    onFirstKeystroke()
                }
                .onSubmit(onCommit)
                .onKeyPress(.escape) {
                    onCancel()
                    return .handled
                }
        }
        .listRowInsets(EdgeInsets(
            top: 4,
            leading: 16 + Double(depth) * 20,
            bottom: 4,
            trailing: 16
        ))
    }
}

#if DEBUG
private struct OutlineEditorPreview: View {
    @State private var showInspector = false
    @State private var store = PreviewFixtures.listStore()

    var body: some View {
        OutlineEditorView(
            store: store,
            showInspector: $showInspector,
            notePreviewLineCount: 1
        )
    }
}

#Preview("Outline Editor") {
    OutlineEditorPreview()
}
#endif

private extension View {
    @ViewBuilder
    func outlineSearch(text: Binding<String>) -> some View {
        #if os(macOS)
        // Deliberately NOT .searchable here: the sidebar already owns this
        // window's search toolbar item, and a second .searchable in the same
        // NavigationSplitView crashes NSToolbar (duplicate item insertion).
        // In-list search on macOS needs its own affordance (e.g. a filter
        // field above the outline) — tracked as a known gap.
        self
        #else
        searchable(text: text, prompt: "Search Items")
        #endif
    }
}
