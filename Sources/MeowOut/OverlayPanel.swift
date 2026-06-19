import AppKit

class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
    
    // 阻止 ESC 短按触发系统默认的取消/关闭行为
    override func cancelOperation(_ sender: Any?) {
        // 故意不做任何事情，ESC 短按由 ScreenOverlayService 的 event tap 来拦截，长按才退出
    }
}
