import AppKit
import ReaderCore

/// Request handling for the debug control channel.
extension AppDelegate {
    func handleControl(_ request: ControlRequest) async -> ControlResponse {
        guard let front = frontController else { return .failure("no window") }
        var handled: Bool?

        switch request.cmd {
        case .state:
            break
        case .key:
            guard let chars = request.chars else { return .failure("key needs chars") }
            handled = pressKey(chars, modifiers: request.modifiers ?? [], in: front)
        case .action:
            guard let name = request.name else { return .failure("action needs name") }
            handled = front.perform(Selector("\(name):"))
        case .find:
            guard let canvas = front.canvas, let text = request.text else {
                return .failure("find needs a document and text")
            }
            canvas.find(text, forward: request.forward ?? true)
        case .select:
            guard let canvas = front.canvas, let page = request.page, let start = request.start, let end = request.end
            else { return .failure("select needs a document, page, start and end") }
            canvas.selection = TextSelection(
                anchor: TextPosition(page: page, index: start), focus: TextPosition(page: page, index: end))
            canvas.needsDisplay = true
        case .open:
            guard let path = request.path else { return .failure("open needs path") }
            handled = open(URL(fileURLWithPath: path), from: front) != nil
        case .wait:
            let deadline = ContinuousClock.now + .seconds(request.timeout ?? 10)
            while !(isSettled(frontController)) {
                guard ContinuousClock.now < deadline else {
                    let canvas = frontController?.canvas?.settleDiagnostics ?? "no canvas"
                    return .failure("not settled within timeout: \(canvas) thumbnailsIdle=\(thumbnailsIdle)")
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
        case .resolve:
            if let chars = request.chars {
                let modifiers = Self.keyModifiers(request.modifiers ?? [])
                guard let modifiers, let shortcut = Self.shortcut(chars, modifiers) else {
                    return .failure("cannot parse shortcut")
                }
                let action = MainMenu.item(for: shortcut)?.action.map(NSStringFromSelector)
                return ControlResponse(ok: true, handled: action != nil, target: action ?? "none")
            }
            guard let name = request.name else { return .failure("resolve needs name or chars") }
            let start: NSResponder? = front.window?.firstResponder ?? front.window
            let action = Selector("\(name):")
            // `handled` here means "enabled": the responder exists and its validation allows the action.
            let responder = start?.chainTarget(for: action, validating: false)
            let enabled = start?.chainTarget(for: action) != nil
            return ControlResponse(
                ok: true, handled: enabled, target: responder.map { String(describing: type(of: $0)) } ?? "none",
                state: controlState(front))
        case .quit:
            Task { NSApp.terminate(nil) }
            return ControlResponse(ok: true)
        }
        return ControlResponse(ok: true, handled: handled, state: controlState(frontController ?? front))
    }

    /// The window a user would be looking at: the key window, else the selected
    /// tab of the frontmost window (tests drive an app that is never active).
    private var frontController: MainWindowController? {
        let all = NSApp.windows.compactMap { $0.windowController as? MainWindowController }
        if let key = all.first(where: { $0.window?.isKeyWindow == true }) { return key }
        let front = NSApp.orderedWindows.first { $0.windowController is MainWindowController && $0.isVisible }
        let selected = front?.tabGroup?.selectedWindow ?? front
        return selected?.windowController as? MainWindowController ?? all.last
    }

    private func isSettled(_ controller: MainWindowController?) -> Bool {
        (controller?.isSettled ?? true) && thumbnailsIdle
    }

    /// Presses a key through the same paths as real typing: ⌘/⌃ shortcuts must
    /// exist in the menu bar (and run that item's action), other keys go to
    /// the canvas key handler.
    private func pressKey(_ chars: String, modifiers names: [String], in controller: MainWindowController) -> Bool {
        guard let modifiers = Self.keyModifiers(names), let shortcut = Self.shortcut(chars, modifiers),
            let (characters, _) = Self.keyCharacters(chars)
        else { return false }

        if shortcut.isMenuShortcut {
            guard let item = MainMenu.item(for: shortcut), let action = item.action else { return false }
            return controller.perform(action)
        }
        guard let canvas = controller.canvas, let window = controller.window else { return false }
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.option) }
        guard
            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0)
        else { return false }
        return canvas.handleKey(event)
    }

    /// "cmd", "shift", "option", "ctrl"; nil for anything else.
    private static func keyModifiers(_ names: [String]) -> KeyModifiers? {
        var modifiers: KeyModifiers = []
        for name in names {
            switch name {
            case "cmd": modifiers.insert(.command)
            case "shift": modifiers.insert(.shift)
            case "option": modifiers.insert(.option)
            case "ctrl": modifiers.insert(.control)
            default: return nil
            }
        }
        return modifiers
    }

    /// The normalized shortcut for a key name or character plus modifiers.
    private static func shortcut(_ chars: String, _ modifiers: KeyModifiers) -> Shortcut? {
        guard let (characters, key) = keyCharacters(chars) else { return nil }
        if let key { return Shortcut(key, modifiers) }
        return Shortcut.fromEvent(characters: characters, modifiers: modifiers)
    }

    /// Named keys ("down", "home", "f3", "space", "return", "escape", "backspace")
    /// or a single character.
    private static func keyCharacters(_ name: String) -> (String, Key?)? {
        func function(_ code: Int) -> String { String(Character(UnicodeScalar(code)!)) }
        switch name {
        case "up": return (function(NSUpArrowFunctionKey), .up)
        case "down": return (function(NSDownArrowFunctionKey), .down)
        case "left": return (function(NSLeftArrowFunctionKey), .left)
        case "right": return (function(NSRightArrowFunctionKey), .right)
        case "home": return (function(NSHomeFunctionKey), .home)
        case "end": return (function(NSEndFunctionKey), .end)
        case "pageup": return (function(NSPageUpFunctionKey), .pageUp)
        case "pagedown": return (function(NSPageDownFunctionKey), .pageDown)
        case "f3": return (function(NSF3FunctionKey), .function(3))
        case "f5": return (function(NSF5FunctionKey), .function(5))
        case "f6": return (function(NSF6FunctionKey), .function(6))
        case "f12": return (function(NSF12FunctionKey), .function(12))
        case "space": return (" ", nil)
        case "return": return ("\r", nil)
        case "escape": return ("\u{1b}", nil)
        case "backspace": return ("\u{7f}", nil)
        default: return name.count == 1 ? (name, nil) : nil
        }
    }

    private func controlState(_ controller: MainWindowController) -> ControlState {
        let canvas = controller.canvas
        let documents = NSApp.windows.compactMap { ($0.windowController as? MainWindowController)?.documentURL?.path }
        let tabWindows = controller.window.map { $0.tabbedWindows ?? [$0] } ?? []
        let frontTabs = tabWindows.map { ($0.windowController as? MainWindowController)?.documentURL?.path ?? "" }
        let visible = NSApp.windows.filter { $0.windowController is MainWindowController && $0.isVisible }
        // Tabs of one window share a tab group; count each group once.
        let windowCount = Set(visible.map { ObjectIdentifier(($0.tabGroup as AnyObject?) ?? $0) }).count
        return ControlState(
            document: controller.documentURL?.path,
            pageCount: canvas?.pageCount ?? 0,
            page: canvas?.currentPage ?? 0,
            zoom: canvas?.zoom,
            zoomPercent: Double(canvas?.layout.zoomPercent ?? 0),
            mode: canvas?.mode,
            rotation: canvas?.rotation ?? 0,
            selectedText: canvas?.selectedText ?? "",
            searchQuery: canvas?.searchQuery,
            match: canvas?.currentMatch.map {
                ControlState.Match(page: $0.page, start: $0.range.lowerBound, end: $0.range.upperBound)
            },
            sidebarVisible: !(controller.currentDocument?.isSidebarCollapsed ?? true),
            presenting: canvas?.isPresenting ?? false,
            invertsColors: canvas?.invertsColors ?? false,
            subtitle: controller.window?.subtitle ?? "",
            openDocuments: documents,
            frontTabs: frontTabs,
            windowCount: windowCount,
            settled: isSettled(controller))
    }
}
