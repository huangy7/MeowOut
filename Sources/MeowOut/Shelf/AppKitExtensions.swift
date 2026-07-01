import AppKit

extension NSScreen {
    /// The screen under the mouse pointer
    static var withMouse: NSScreen {
        let mouse = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(mouse) } ?? main ?? screens[0]
    }
}
