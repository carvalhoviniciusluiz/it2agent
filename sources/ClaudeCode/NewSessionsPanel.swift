//
//  NewSessionsPanel.swift
//  iTerm2SharedARC
//
//  The "New Sessions" dialog (it2agent). A modal sheet that batch-creates
//  terminal sessions: a top line shows the current working directory with a
//  "Use current path" checkbox, followed by a dynamic list of rows (a session
//  name + a "Group in new window" checkbox each) with add/remove controls. On
//  Create, the rows are handed to NewSessionsLauncher.
//
//  Modeled on AddClippingPanel: a programmatic NSPanel presented via
//  beginSheet, laid out with manual frames (no auto layout), Enter=Create /
//  Escape=Cancel. Rows live in a flipped container inside an NSScrollView so an
//  arbitrary number of rows scrolls rather than growing the panel.
//

import AppKit
import Foundation

@objc(iTerm2NewSessionsPanel)
class NewSessionsPanel: NSObject, NSTextFieldDelegate {
    // Keeps the panel (and thus `self`) alive while the sheet is up.
    private static var current: NewSessionsPanel?

    private var window: NSPanel?
    private let cwdValueField = NSTextField(labelWithString: "")
    private let useCurrentPathCheckbox = NSButton(checkboxWithTitle: "Use current path",
                                                  target: nil, action: nil)
    private let rowsContainer = FlippedView()
    private let scrollView = NSScrollView()
    private let createButton = NSButton()
    private var rows: [RowViews] = []
    private var currentCwd: String?

    private final class RowViews {
        let name = NSTextField()
        let group = NSButton(checkboxWithTitle: "Group in new window", target: nil, action: nil)
        let remove = NSButton(title: "\u{2013}", target: nil, action: nil)   // en dash
    }

    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    // Layout constants.
    private let pad: CGFloat = 16
    private let rowH: CGFloat = 30
    private let controlH: CGFloat = 22
    private let checkboxW: CGFloat = 176
    private let removeW: CGFloat = 28
    private let gap: CGFloat = 8

    @objc(presentOverWindow:)
    func present(over parentWindow: NSWindow) {
        NewSessionsPanel.current = self

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 420),
                            styleMask: [.titled],
                            backing: .buffered,
                            defer: true)
        panel.title = "New Sessions"
        panel.isFloatingPanel = false
        let content = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        content.autoresizingMask = [.width, .height]
        panel.contentView = content
        self.window = panel

        buildContent(in: content)
        addRow()                 // start with one empty row
        updateCreateEnabled()
        loadCurrentWorkingDirectory()

        parentWindow.beginSheet(panel) { [weak self] response in
            guard let self else { return }
            let specs = self.collectSpecs()
            let cwd = (self.useCurrentPathCheckbox.state == .on) ? self.currentCwd : nil
            self.window = nil
            NewSessionsPanel.current = nil
            if response == .OK {
                NewSessionsLauncher.launch(specs, workingDirectory: cwd)
            }
        }

        if let first = rows.first {
            panel.makeFirstResponder(first.name)
        }
    }

    // MARK: - Building

    private func buildContent(in container: NSView) {
        let W = container.bounds.width
        let H = container.bounds.height

        // Bottom: Cancel + Create.
        let buttonH: CGFloat = 32
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        cancel.sizeToFit()
        let cancelW = max(84, cancel.frame.width)
        cancel.frame = NSRect(x: W - pad - cancelW * 2 - gap, y: pad, width: cancelW, height: buttonH)
        cancel.autoresizingMask = [.minXMargin, .maxYMargin]
        container.addSubview(cancel)

        createButton.title = "Create"
        createButton.target = self
        createButton.action = #selector(createClicked)
        createButton.bezelStyle = .rounded
        createButton.keyEquivalent = "\r"
        createButton.sizeToFit()
        let createW = max(84, createButton.frame.width)
        createButton.frame = NSRect(x: W - pad - createW, y: pad, width: createW, height: buttonH)
        createButton.autoresizingMask = [.minXMargin, .maxYMargin]
        container.addSubview(createButton)

        // Above buttons: "Add session".
        let addH: CGFloat = 26
        let addBtn = NSButton(title: "+ Add session", target: self, action: #selector(addClicked))
        addBtn.bezelStyle = .rounded
        addBtn.sizeToFit()
        let addBtnY = pad + buttonH + gap
        addBtn.frame = NSRect(x: pad, y: addBtnY, width: max(120, addBtn.frame.width), height: addH)
        addBtn.autoresizingMask = [.maxXMargin, .maxYMargin]
        container.addSubview(addBtn)

        // Top: working-directory line + "Use current path" checkbox.
        let caption = NSTextField(labelWithString: "Working directory:")
        caption.frame = NSRect(x: pad, y: H - pad - controlH, width: 130, height: controlH)
        caption.autoresizingMask = [.minYMargin]
        container.addSubview(caption)

        cwdValueField.frame = NSRect(x: pad + 130 + gap, y: H - pad - controlH,
                                     width: W - pad - (pad + 130 + gap), height: controlH)
        cwdValueField.autoresizingMask = [.width, .minYMargin]
        cwdValueField.lineBreakMode = .byTruncatingMiddle
        cwdValueField.stringValue = "\u{2026}"
        container.addSubview(cwdValueField)

        useCurrentPathCheckbox.state = .on
        useCurrentPathCheckbox.frame = NSRect(x: pad, y: H - pad - controlH * 2 - 6,
                                              width: W - pad * 2, height: controlH)
        useCurrentPathCheckbox.autoresizingMask = [.width, .minYMargin]
        container.addSubview(useCurrentPathCheckbox)

        // Middle: scroll view holding the dynamic rows.
        let scrollTop = useCurrentPathCheckbox.frame.minY - gap
        let scrollBottom = addBtnY + addH + gap
        scrollView.frame = NSRect(x: pad, y: scrollBottom,
                                  width: W - pad * 2, height: scrollTop - scrollBottom)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        rowsContainer.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: 0)
        rowsContainer.autoresizingMask = [.width]
        scrollView.documentView = rowsContainer
        container.addSubview(scrollView)
    }

    // MARK: - Rows

    private func addRow() {
        let row = RowViews()
        row.name.delegate = self
        row.name.bezelStyle = .roundedBezel
        row.name.placeholderString = "Session name"
        row.group.target = self
        row.group.action = #selector(checkboxToggled)
        row.remove.bezelStyle = .rounded
        row.remove.target = self
        row.remove.action = #selector(removeClicked(_:))
        row.remove.setButtonType(.momentaryPushIn)
        rows.append(row)
        rebuildRows()
        updateCreateEnabled()
        window?.makeFirstResponder(row.name)
    }

    @objc private func removeClicked(_ sender: NSButton) {
        guard rows.count > 1,
              let idx = rows.firstIndex(where: { $0.remove === sender }) else {
            return
        }
        rows.remove(at: idx)
        rebuildRows()
        updateCreateEnabled()
    }

    private func rebuildRows() {
        rowsContainer.subviews.forEach { $0.removeFromSuperview() }
        let cw = scrollView.contentSize.width
        let nameW = max(120, cw - checkboxW - removeW - gap * 2)
        let y0 = (rowH - controlH) / 2
        for (i, row) in rows.enumerated() {
            let top = CGFloat(i) * rowH
            row.name.frame = NSRect(x: 0, y: top + y0, width: nameW, height: controlH)
            row.name.autoresizingMask = [.width]
            rowsContainer.addSubview(row.name)

            row.group.frame = NSRect(x: nameW + gap, y: top + y0, width: checkboxW, height: controlH)
            row.group.autoresizingMask = [.minXMargin]
            rowsContainer.addSubview(row.group)

            row.remove.frame = NSRect(x: cw - removeW, y: top + y0, width: removeW, height: controlH)
            row.remove.autoresizingMask = [.minXMargin]
            row.remove.isEnabled = rows.count > 1
            rowsContainer.addSubview(row.remove)
        }
        let totalH = max(scrollView.contentSize.height, CGFloat(rows.count) * rowH)
        rowsContainer.frame = NSRect(x: 0, y: 0, width: cw, height: totalH)
        // Keep the newest row visible.
        rowsContainer.scrollToVisible(NSRect(x: 0, y: totalH - rowH, width: cw, height: rowH))
    }

    // MARK: - State

    private func collectSpecs() -> [NewSessionSpec] {
        rows.map { NewSessionSpec(name: $0.name.stringValue, groupInNewWindow: $0.group.state == .on) }
    }

    private func updateCreateEnabled() {
        let hasValid = rows.contains {
            !$0.name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        createButton.isEnabled = hasValid
    }

    func controlTextDidChange(_ obj: Notification) {
        updateCreateEnabled()
    }

    // Pressing Enter/Return in a session-name field adds a new row (as if
    // "+ Add session" were clicked) and moves focus to it, instead of firing the
    // default Create button. Returning true consumes the newline so it does not
    // propagate to the default button.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            addRow()
            return true
        }
        return false
    }

    @objc private func checkboxToggled() {}

    private func loadCurrentWorkingDirectory() {
        let controller = iTermController.sharedInstance()
        let terminal = controller?.keyTerminalWindow() ?? controller?.currentTerminal
        guard let session = terminal?.currentSession() else {
            cwdValueField.stringValue = "(no active session)"
            return
        }
        session.asyncCurrentLocalWorkingDirectory { [weak self] pwd in
            guard let self else { return }
            self.currentCwd = pwd
            self.cwdValueField.stringValue = (pwd?.isEmpty == false) ? pwd! : "(unknown)"
        }
    }

    // MARK: - Actions

    @objc private func addClicked() {
        addRow()
    }

    @objc private func createClicked() {
        guard createButton.isEnabled, let window else { return }
        window.sheetParent?.endSheet(window, returnCode: .OK)
    }

    @objc private func cancelClicked() {
        guard let window else { return }
        window.sheetParent?.endSheet(window, returnCode: .cancel)
    }
}
