//
//  NewSessionsLauncher.swift
//  iTerm2SharedARC
//
//  Batch launcher for the "New Sessions" dialog (it2agent). Opens N named
//  sessions in one shot: rows without "Group in new window" become tabs in the
//  current window; rows with it become tabs of a single, shared new window.
//
//  The per-session launch mirrors the shipping pattern in
//  OrchestratorDispatcher.start_session: overlay KEY_NAME (+ optional custom
//  working directory) on the default profile and hand it to iTermSessionLauncher
//  at creation time — so name/cwd are set when the session is born (no racy
//  post-launch typing, cf. it2agent #74).
//

import AppKit
import Foundation

/// One requested session: a name and whether it belongs to the shared new window.
@objc(iTerm2NewSessionSpec)
class NewSessionSpec: NSObject {
    @objc let name: String
    @objc let groupInNewWindow: Bool

    @objc init(name: String, groupInNewWindow: Bool) {
        self.name = name
        self.groupInNewWindow = groupInNewWindow
        super.init()
    }

    var hasValidName: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@objc(iTerm2NewSessionsLauncher)
class NewSessionsLauncher: NSObject {
    /// Split specs into (tabs-in-current-window, grouped-in-new-window),
    /// dropping blank names. Pure — unit-testable without a running app.
    @objc(partitionSpecs:)
    static func partition(_ specs: [NewSessionSpec]) -> [[NewSessionSpec]] {
        let valid = specs.filter { $0.hasValidName }
        let tabs = valid.filter { !$0.groupInNewWindow }
        let windowGroup = valid.filter { $0.groupInNewWindow }
        return [tabs, windowGroup]
    }

    /// Open every valid spec. `cwd` nil ⇒ each session uses the profile's default
    /// initial directory; non-nil ⇒ all sessions open in `cwd`.
    @objc(launchSpecs:workingDirectory:)
    static func launch(_ specs: [NewSessionSpec], workingDirectory cwd: String?) {
        let parts = partition(specs)
        let tabs = parts[0]
        let windowGroup = parts[1]
        guard !tabs.isEmpty || !windowGroup.isEmpty else {
            return
        }

        let controller = iTermController.sharedInstance()
        let current = controller?.keyTerminalWindow() ?? controller?.currentTerminal

        // Tabs go into the current window; if there is none, the first makes a
        // window and the rest tab into it.
        launchSequence(tabs, cwd: cwd, into: current)
        // The grouped rows always land in one dedicated new window.
        launchSequence(windowGroup, cwd: cwd, into: nil)
    }

    /// If `terminal` is non-nil, open every spec as a tab in it. Otherwise the
    /// first spec opens a NEW window and the rest tab into that same window
    /// (resolved from the created session, so the group stays together).
    private static func launchSequence(_ specs: [NewSessionSpec],
                                       cwd: String?,
                                       into terminal: PseudoTerminal?) {
        guard let first = specs.first else {
            return
        }
        if let terminal {
            for spec in specs {
                launchOne(spec.name, cwd: cwd, style: .tab, inTerminal: terminal, completion: nil)
            }
            return
        }
        let rest = Array(specs.dropFirst())
        launchOne(first.name, cwd: cwd, style: .window, inTerminal: nil) { session in
            let newWindow = session.flatMap { iTermController.sharedInstance()?.terminal(with: $0) }
            for spec in rest {
                launchOne(spec.name, cwd: cwd, style: .tab, inTerminal: newWindow, completion: nil)
            }
        }
    }

    private static func launchOne(_ name: String,
                                  cwd: String?,
                                  style: iTermOpenStyle,
                                  inTerminal: PseudoTerminal?,
                                  completion: ((PTYSession?) -> Void)?) {
        guard let base = ProfileModel.sharedInstance().defaultProfile() else {
            completion?(nil)
            return
        }
        var mutable = base
        mutable[KEY_NAME] = name
        if let cwd, !cwd.isEmpty {
            mutable[KEY_CUSTOM_DIRECTORY] = kProfilePreferenceInitialDirectoryCustomValue
            mutable[KEY_WORKING_DIRECTORY] = cwd
        }
        iTermSessionLauncher.launchBookmark(mutable,
                                            in: inTerminal,
                                            style: style,
                                            withURL: nil,
                                            hotkeyWindowType: .none,
                                            makeKey: true,
                                            canActivate: true,
                                            respectTabbingMode: false,
                                            index: nil,
                                            command: nil,
                                            makeSession: nil,
                                            didMakeSession: nil,
                                            completion: { session, ok in
            completion?(ok ? session : nil)
        })
    }
}
