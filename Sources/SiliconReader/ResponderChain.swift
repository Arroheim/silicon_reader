import AppKit

extension NSResponder {
    /// The first object that handles `action` starting here: this responder's
    /// chain (views, view controllers, window, window controller), then the
    /// application and its delegate — and whose menu validation allows it.
    ///
    /// Unlike `NSApp.sendAction(_:to: nil, from:)` this doesn't depend on which
    /// window is key, so commands reach the window they came from even when
    /// the app isn't active (e.g. driven by the e2e control channel).
    @MainActor
    func chainTarget(for action: Selector) -> AnyObject? {
        var candidates: [AnyObject] = []
        var responder: NSResponder? = self
        while let current = responder {
            candidates.append(current)
            responder = current.nextResponder
        }
        candidates.append(NSApp)
        if let delegate = NSApp.delegate { candidates.append(delegate) }

        guard let target = candidates.first(where: { $0.responds(to: action) }) else { return nil }
        if let validator = target as? NSMenuItemValidation,
            !validator.validateMenuItem(NSMenuItem(title: "", action: action, keyEquivalent: ""))
        {
            return nil
        }
        return target
    }

    /// Sends `action` to `chainTarget(for:)`; false if nothing took it.
    @MainActor
    @discardableResult
    func sendThroughChain(_ action: Selector, from sender: Any? = nil) -> Bool {
        guard let target = chainTarget(for: action) else { return false }
        return NSApp.sendAction(action, to: target, from: sender)
    }
}
