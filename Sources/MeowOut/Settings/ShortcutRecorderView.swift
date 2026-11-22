// Sources/MeowOut/Settings/ShortcutRecorderView.swift
import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI

/// 统一的全局快捷键胶囊录制视图：替代上游默认搜索框风格的 Recorder，
/// 自动同步应用内语言、SwiftUI 禁用态，并提供实时修饰键反馈与冲突检测。
struct ShortcutRecorderView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.isEnabled) private var isEnabled

    let name: KeyboardShortcuts.Name
    var onChange: ((KeyboardShortcuts.Shortcut?) -> Void)? = nil

    init(
        for name: KeyboardShortcuts.Name,
        onChange: ((KeyboardShortcuts.Shortcut?) -> Void)? = nil
    ) {
        self.name = name
        self.onChange = onChange
    }

    var body: some View {
        ShortcutRecorderRepresentable(
            name: name,
            language: appState.language,
            isEnabled: isEnabled,
            onChange: onChange
        )
        .fixedSize()
    }
}

private struct ShortcutRecorderRepresentable: NSViewRepresentable {
    let name: KeyboardShortcuts.Name
    let language: AppState.AppLanguage
    let isEnabled: Bool
    let onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let control = ShortcutRecorderControl(for: name, language: language, onChange: onChange)
        control.isEnabled = isEnabled
        return control
    }

    func updateNSView(_ nsView: ShortcutRecorderControl, context: Context) {
        nsView.shortcutName = name
        nsView.language = language
        nsView.onChange = onChange
        nsView.isEnabled = isEnabled
    }
}

/// macOS 原生单体胶囊式全局快捷键录制控件（纯 NSControl 实现，彻底屏蔽搜索框与输入法干扰）。
final class ShortcutRecorderControl: NSControl {
    private static let shortcutChangedNotification = Notification.Name("KeyboardShortcuts_shortcutByNameDidChange")

    private let controlHeight: CGFloat = 24.0
    var onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?

    private var canBecomeKey = false
    private var isHovered = false
    private var shortcutsNameChangeObserver: NSObjectProtocol?
    private var windowDidResignKeyObserver: NSObjectProtocol?
    private var windowDidBecomeKeyObserver: NSObjectProtocol?
    private var mouseEventMonitor: Any?
    private var trackingArea: NSTrackingArea?

    private var labelTrailingToClearConstraint: NSLayoutConstraint?
    private var labelTrailingToSelfConstraint: NSLayoutConstraint?

    private(set) var isRecording = false
    private var currentModifiers: NSEvent.ModifierFlags = []
    private var temporaryNotice: String?

    var shortcutName: KeyboardShortcuts.Name {
        didSet {
            guard shortcutName != oldValue else { return }
            updateUI()
        }
    }

    var language: AppState.AppLanguage {
        didSet {
            guard language != oldValue else { return }
            clearButton.toolTip = I18n.localized("shortcut_clear_tooltip", language: language)
            updateUI()
        }
    }

    override var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            if !isEnabled && isRecording {
                endRecording(cancelled: true)
                window?.makeFirstResponder(nil)
            }
            updateUI()
        }
    }

    /// 显式屏蔽系统输入法与 TSM 文本服务引擎，录制快捷键时绝不弹出中文候选框。
    override var inputContext: NSTextInputContext? { nil }

    override var acceptsFirstResponder: Bool { canBecomeKey && isEnabled }
    override var canBecomeKeyView: Bool { canBecomeKey && isEnabled }
    override var focusRingType: NSFocusRingType {
        get { .none }
        set { /* 统一采用胶囊内建强调色边框，不绘制外溢焦点环 */ }
    }

    private var hasShortcut: Bool {
        KeyboardShortcuts.getShortcut(for: shortcutName) != nil
    }

    private let displayLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.lineBreakMode = .byClipping
        label.isSelectable = false
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private lazy var clearButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.setButtonType(.momentaryChange)
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        button.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: I18n.localized("shortcut_clear_tooltip", language: language)
        )?.withSymbolConfiguration(config)
        button.contentTintColor = .tertiaryLabelColor
        button.toolTip = I18n.localized("shortcut_clear_tooltip", language: language)
        button.target = self
        button.action = #selector(clearButtonClicked)
        return button
    }()

    init(
        for name: KeyboardShortcuts.Name,
        language: AppState.AppLanguage,
        onChange: ((KeyboardShortcuts.Shortcut?) -> Void)? = nil
    ) {
        self.shortcutName = name
        self.language = language
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 108, height: controlHeight))

        setupUI()
        setupEvents()
        updateUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let monitor = mouseEventMonitor {
            DispatchQueue.main.async {
                NSEvent.removeMonitor(monitor)
            }
        }
        if let observer = shortcutsNameChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = windowDidResignKeyObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = windowDidBecomeKeyObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 5.5
        layer?.masksToBounds = true

        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(displayLabel)
        addSubview(clearButton)

        let centerYConstraint = displayLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        let leadingConstraint = displayLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9)
        let heightConstraint = heightAnchor.constraint(equalToConstant: controlHeight)
        let minWidthConstraint = widthAnchor.constraint(greaterThanOrEqualToConstant: 88)

        let clearCenter = clearButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        let clearTrailing = clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)
        let clearWidth = clearButton.widthAnchor.constraint(equalToConstant: 13)
        let clearHeight = clearButton.heightAnchor.constraint(equalToConstant: 13)

        labelTrailingToClearConstraint = clearButton.leadingAnchor.constraint(equalTo: displayLabel.trailingAnchor, constant: 5)
        labelTrailingToSelfConstraint = trailingAnchor.constraint(equalTo: displayLabel.trailingAnchor, constant: 9)

        NSLayoutConstraint.activate([
            centerYConstraint,
            leadingConstraint,
            heightConstraint,
            minWidthConstraint,
            clearCenter,
            clearTrailing,
            clearWidth,
            clearHeight,
        ])
    }

    override var intrinsicContentSize: NSSize {
        let labelSize = displayLabel.intrinsicContentSize
        let clearWidth: CGFloat = (hasShortcut && !isRecording && isEnabled) ? 19 : 0
        // 宽度至少容纳录制提示语与占位语，进出录制与按住修饰键时右对齐左边缘不抖动
        let promptFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        let pressPromptWidth = (I18n.localized("shortcut_press_prompt", language: language) as NSString)
            .size(withAttributes: [.font: promptFont]).width
        let recordPromptWidth = (I18n.localized("shortcut_record_placeholder", language: language) as NSString)
            .size(withAttributes: [.font: promptFont]).width
        let minStableWidth = max(88, pressPromptWidth + 18, recordPromptWidth + 18)
        let width = ceil(max(minStableWidth, labelSize.width + 18 + clearWidth))
        return NSSize(width: width, height: controlHeight)
    }

    private func setupEvents() {
        shortcutsNameChangeObserver = NotificationCenter.default.addObserver(
            forName: Self.shortcutChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self,
                      let changedName = notification.userInfo?["name"] as? KeyboardShortcuts.Name,
                      changedName == self.shortcutName else {
                    return
                }
                self.updateUI()
            }
        }
    }

    private func updateUI() {
        guard let layer else { return }

        let shouldShowClear = hasShortcut && !isRecording && isEnabled
        if shouldShowClear {
            labelTrailingToSelfConstraint?.isActive = false
            labelTrailingToClearConstraint?.isActive = true
            clearButton.isHidden = false
        } else {
            labelTrailingToClearConstraint?.isActive = false
            labelTrailingToSelfConstraint?.isActive = true
            clearButton.isHidden = true
        }

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let hairline = 1.0 / max(window?.backingScaleFactor ?? 1.0, 1.0)

        if isRecording {
            layer.borderColor = NSColor.controlAccentColor.cgColor
            layer.borderWidth = 1
            layer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(isDark ? 0.14 : 0.07).cgColor
        } else if isDark {
            layer.borderColor = NSColor(white: 1.0, alpha: isHovered && isEnabled ? 0.16 : 0.10).cgColor
            layer.borderWidth = hairline
            let baseAlpha: CGFloat = (isHovered && isEnabled) ? 0.17 : 0.10
            layer.backgroundColor = NSColor(white: 1.0, alpha: baseAlpha).cgColor
        } else {
            layer.borderColor = NSColor.separatorColor.withAlphaComponent(isHovered && isEnabled ? 0.35 : 0.22).cgColor
            layer.borderWidth = hairline
            let baseAlpha: CGFloat = (isHovered && isEnabled) ? 0.11 : 0.055
            layer.backgroundColor = NSColor.labelColor.withAlphaComponent(baseAlpha).cgColor
        }

        if let notice = temporaryNotice {
            displayLabel.stringValue = notice
            displayLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
            displayLabel.textColor = .systemOrange
        } else if isRecording {
            displayLabel.font = .systemFont(ofSize: 11, weight: .medium)
            if currentModifiers.isEmpty {
                displayLabel.textColor = .secondaryLabelColor
                displayLabel.stringValue = I18n.localized("shortcut_press_prompt", language: language)
            } else {
                displayLabel.textColor = .labelColor
                displayLabel.stringValue = ShortcutDisplayFormatter.formatLiveModifiers(currentModifiers)
            }
        } else if let shortcut = KeyboardShortcuts.getShortcut(for: shortcutName) {
            displayLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
            displayLabel.textColor = isEnabled ? .labelColor : .tertiaryLabelColor
            displayLabel.stringValue = ShortcutDisplayFormatter.format(shortcut: shortcut)
        } else {
            displayLabel.font = .systemFont(ofSize: 11, weight: .regular)
            displayLabel.textColor = isEnabled ? .secondaryLabelColor : .tertiaryLabelColor
            displayLabel.stringValue = I18n.localized("shortcut_record_placeholder", language: language)
        }

        invalidateIntrinsicContentSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateUI()
    }

    override func updateLayer() {
        super.updateLayer()
        updateUI()
    }

    // MARK: - 录制生命周期与外部点击安全退出

    private func startRecording() {
        guard !isRecording, isEnabled else { return }
        isRecording = true
        currentModifiers = []
        temporaryNotice = nil
        removeEventMonitor()

        mouseEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isRecording else { return event }

            guard let window = self.window, event.window == window else {
                self.endRecording(cancelled: true)
                self.window?.makeFirstResponder(nil)
                return event
            }

            let locationInView = self.convert(event.locationInWindow, from: nil)
            if self.bounds.contains(locationInView) {
                self.endRecording(cancelled: true)
                self.window?.makeFirstResponder(nil)
                return nil
            }

            self.endRecording(cancelled: true)
            self.window?.makeFirstResponder(nil)
            return event
        }

        ShortcutRecordingGate.shared.beginRecording()
        updateUI()
    }

    private func endRecording(cancelled: Bool) {
        guard isRecording else { return }
        isRecording = false
        currentModifiers = []
        temporaryNotice = nil
        removeEventMonitor()
        ShortcutRecordingGate.shared.endRecording()
        updateUI()
    }

    private func removeEventMonitor() {
        guard let monitor = mouseEventMonitor else { return }
        mouseEventMonitor = nil
        DispatchQueue.main.async {
            NSEvent.removeMonitor(monitor)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            startRecording()
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        endRecording(cancelled: true)
        return super.resignFirstResponder()
    }

    // MARK: - 键盘事件与冲突校验

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
        currentModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        updateUI()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else {
            return super.performKeyEquivalent(with: event)
        }
        return processKeyEvent(event)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        _ = processKeyEvent(event)
    }

    @discardableResult
    private func processKeyEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let isFunctionKey = ShortcutInputValidator.isFunctionKeyCode(event.keyCode)

        switch ShortcutInputValidator.classify(keyCode: event.keyCode, modifiers: modifiers, isFunctionKey: isFunctionKey) {
        case .cancel:
            endRecording(cancelled: true)
            window?.makeFirstResponder(nil)
            return true

        case .clear:
            saveShortcut(nil)
            endRecording(cancelled: false)
            window?.makeFirstResponder(nil)
            return true

        case .moveFocus:
            endRecording(cancelled: true)
            window?.selectNextKeyView(nil)
            return true

        case .requiresModifier:
            showModifierRequiredNotice()
            return true

        case .recordable:
            break
        }

        guard let shortcut = KeyboardShortcuts.Shortcut(event: event) else {
            showModifierRequiredNotice()
            return true
        }

        // 1. 应用内 7 个快捷键互撞检测
        if let conflict = AppShortcutRegistry.conflictingEntry(for: shortcut, excluding: shortcutName) {
            let featureName = I18n.localized(conflict.titleKey, language: language)
            let formatted = ShortcutDisplayFormatter.format(shortcut: shortcut)
            let message = I18n.localizedFormat("shortcut_conflict_in_app", language: language, formatted, featureName)
            presentWarningSheet(message: message)
            endRecording(cancelled: true)
            window?.makeFirstResponder(nil)
            return true
        }

        // 2. 应用主菜单快捷键冲突检测
        if let menuTitle = ShortcutInputValidator.conflictingMainMenuItemTitle(for: shortcut) {
            let message = I18n.localizedFormat("shortcut_conflict_main_menu", language: language, menuTitle)
            presentWarningSheet(message: message)
            endRecording(cancelled: true)
            window?.makeFirstResponder(nil)
            return true
        }

        // 3. macOS 15.0-15.1 沙盒 Option-only 限制
        if ShortcutInputValidator.isDisallowedInSandbox(modifiers: shortcut.modifiers) {
            let message = I18n.localized("shortcut_disallowed_sandbox", language: language)
            presentWarningSheet(message: message)
            endRecording(cancelled: true)
            window?.makeFirstResponder(nil)
            return true
        }

        saveShortcut(shortcut)
        endRecording(cancelled: false)
        window?.makeFirstResponder(nil)
        return true
    }

    private func presentWarningSheet(message: String) {
        let hostWindow = self.window
        DispatchQueue.main.async {
            guard let hostWindow else { return }
            let alert = NSAlert()
            alert.messageText = message
            alert.alertStyle = .warning
            alert.beginSheetModal(for: hostWindow, completionHandler: nil)
        }
    }

    private func showModifierRequiredNotice() {
        temporaryNotice = I18n.localized("shortcut_modifier_required", language: language)
        updateUI()
        shakeAnimation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            guard let self, self.isRecording else { return }
            self.temporaryNotice = nil
            self.updateUI()
        }
    }

    private func shakeAnimation() {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.duration = 0.25
        animation.values = [-3, 3, -2, 2, -1, 1, 0]
        layer?.add(animation, forKey: "shake")
    }

    @objc private func clearButtonClicked() {
        guard isEnabled else { return }
        saveShortcut(nil)
        endRecording(cancelled: false)
    }

    @objc private func resetToDefaultClicked() {
        guard isEnabled, let defaultShortcut = shortcutName.defaultShortcut else { return }
        if let conflict = AppShortcutRegistry.conflictingEntry(for: defaultShortcut, excluding: shortcutName) {
            let featureName = I18n.localized(conflict.titleKey, language: language)
            let formatted = ShortcutDisplayFormatter.format(shortcut: defaultShortcut)
            let message = I18n.localizedFormat("shortcut_conflict_in_app", language: language, formatted, featureName)
            presentWarningSheet(message: message)
            return
        }
        saveShortcut(defaultShortcut)
    }

    private func saveShortcut(_ shortcut: KeyboardShortcuts.Shortcut?) {
        KeyboardShortcuts.setShortcut(shortcut, for: shortcutName)
        onChange?(shortcut)
        updateUI()
    }

    // MARK: - 鼠标交互与右键快捷菜单

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        let location = convert(event.locationInWindow, from: nil)
        if clearButton.frame.contains(location) && hasShortcut && !isRecording {
            clearButtonClicked()
            return
        }
        if !isRecording {
            window?.makeFirstResponder(self)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard isEnabled, !isRecording else { return nil }
        let contextMenu = NSMenu()
        let current = KeyboardShortcuts.getShortcut(for: shortcutName)

        if let defaultShortcut = shortcutName.defaultShortcut, current != defaultShortcut {
            let resetItem = NSMenuItem(
                title: I18n.localized("shortcut_reset_default", language: language),
                action: #selector(resetToDefaultClicked),
                keyEquivalent: ""
            )
            resetItem.target = self
            contextMenu.addItem(resetItem)
        }

        if current != nil {
            let clearItem = NSMenuItem(
                title: I18n.localized("shortcut_clear_tooltip", language: language),
                action: #selector(clearButtonClicked),
                keyEquivalent: ""
            )
            clearItem.target = self
            contextMenu.addItem(clearItem)
        }

        return contextMenu.items.isEmpty ? nil : contextMenu
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            endRecording(cancelled: true)
            removeEventMonitor()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        if let observer = windowDidResignKeyObserver {
            NotificationCenter.default.removeObserver(observer)
            windowDidResignKeyObserver = nil
        }
        if let observer = windowDidBecomeKeyObserver {
            NotificationCenter.default.removeObserver(observer)
            windowDidBecomeKeyObserver = nil
        }

        guard let window else {
            endRecording(cancelled: true)
            removeEventMonitor()
            return
        }

        windowDidResignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                _ = self?.window?.makeFirstResponder(nil)
            }
        }

        windowDidBecomeKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.preventBecomingKey()
            }
        }

        preventBecomingKey()
    }

    private func preventBecomingKey() {
        canBecomeKey = false
        DispatchQueue.main.async { [weak self] in
            self?.canBecomeKey = true
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isRecording, isEnabled else { return }
        isHovered = true
        clearButton.contentTintColor = .secondaryLabelColor
        updateUI()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        clearButton.contentTintColor = .tertiaryLabelColor
        if !isRecording {
            updateUI()
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}
