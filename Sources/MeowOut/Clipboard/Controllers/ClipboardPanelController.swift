import Cocoa
import SwiftUI

private final class ClipboardPanelVisualEffectView: NSVisualEffectView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
public final class ClipboardPanelController: NSPanel {
    public static let shared = ClipboardPanelController()

    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var appState: AppState?

    public let viewModel: ClipboardPanelViewModel

    private init() {
        viewModel = ClipboardPanelViewModel()

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 620),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        level = .popUpMenu
        isFloatingPanel = true
        worksWhenModal = true
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        let visualEffect = ClipboardPanelVisualEffectView()
        visualEffect.material = .popover
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow

        let hostingView = makeHostingView()
        visualEffect.addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])

        contentView = visualEffect
    }

    public func configure(appState: AppState) {
        self.appState = appState
        rebuildHostingView()
    }

    public func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    public func show() {
        viewModel.reset()
        setFrame(frameNearMouse(), display: true)
        makeKeyAndOrderFront(nil)
        setupMonitors()
    }

    public func hide() {
        orderOut(nil)
        removeMonitors()
    }

    public override var canBecomeKey: Bool {
        true
    }

    private func setupMonitors() {
        removeMonitors()

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else {
                return event
            }

            switch event.type {
            case .keyDown:
                return self.handleKeyDown(event) ? nil : event
            case .leftMouseDown, .rightMouseDown:
                self.hideIfLocalClickIsOutsidePanel(event)
                return event
            default:
                return event
            }
        }
    }

    private func makeHostingView() -> NSHostingView<ClipboardPanelView> {
        NSHostingView(
            rootView: ClipboardPanelView(
                viewModel: viewModel,
                language: appState?.language ?? .system
            ) { [weak self] index in
                _ = self?.chooseItem(at: index)
            }
        )
    }

    private func rebuildHostingView() {
        guard let visualEffect = contentView as? NSVisualEffectView else {
            return
        }

        visualEffect.subviews.forEach { $0.removeFromSuperview() }
        let hostingView = makeHostingView()
        visualEffect.addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])
    }

    private func removeMonitors() {
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }

        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    private func frameNearMouse() -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main

        var panelRect = frame
        panelRect.origin.x = mouseLocation.x - panelRect.width / 2
        panelRect.origin.y = mouseLocation.y - panelRect.height - 20

        guard let screenFrame = screen?.visibleFrame else {
            return panelRect
        }

        let inset: CGFloat = 10
        if panelRect.minX < screenFrame.minX {
            panelRect.origin.x = screenFrame.minX + inset
        }
        if panelRect.maxX > screenFrame.maxX {
            panelRect.origin.x = screenFrame.maxX - panelRect.width - inset
        }
        if panelRect.minY < screenFrame.minY {
            panelRect.origin.y = screenFrame.minY + inset
        }
        if panelRect.maxY > screenFrame.maxY {
            panelRect.origin.y = screenFrame.maxY - panelRect.height - inset
        }

        return panelRect
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let keyCode = event.keyCode
        let flags = event.modifierFlags
        let isCommand = flags.contains(.command)
        let isShift = flags.contains(.shift)
        let isOption = flags.contains(.option)

        switch keyCode {
        case 53:
            hide()
            return true
        case 125:
            viewModel.moveSelection(up: false)
            return true
        case 126:
            viewModel.moveSelection(up: true)
            return true
        case 36, 76:
            chooseSelected(
                removeFormatting: isCommand && isShift,
                pasteAutomaticallyOverride: isOption ? !ClipboardHistorySettings.shared.pasteAutomatically : nil
            )
            return true
        case 51:
            if viewModel.removeLastSearchCharacter() {
                return true
            }
            return true
        case 117:
            viewModel.deleteSelected()
            return true
        case 35 where isCommand:
            viewModel.togglePinnedSelected()
            return true
        default:
            if handleCommandNumber(event, isCommand: isCommand) {
                return true
            }

            if !isCommand, !flags.contains(.control), let characters = event.charactersIgnoringModifiers {
                return appendPrintableSearch(characters)
            }
        }

        return false
    }

    private func handleCommandNumber(_ event: NSEvent, isCommand: Bool) -> Bool {
        guard isCommand,
              let characters = event.charactersIgnoringModifiers,
              characters.count == 1,
              let number = Int(characters),
              number >= 1,
              number <= 9
        else {
            return false
        }

        return chooseItem(at: number - 1)
    }

    private func appendPrintableSearch(_ characters: String) -> Bool {
        guard characters.rangeOfCharacter(from: .controlCharacters) == nil else {
            return false
        }

        viewModel.appendSearch(characters)
        return true
    }

    private func chooseSelected(
        removeFormatting: Bool = false,
        pasteAutomaticallyOverride: Bool? = nil
    ) {
        guard viewModel.selectedItem != nil else {
            return
        }

        ClipboardPanelSelectionCoordinator.chooseAfterDismiss(
            dismiss: { [weak self] in
                self?.hide()
            },
            choose: { [weak self] in
                self?.viewModel.chooseSelected(
                    removeFormatting: removeFormatting,
                    pasteAutomaticallyOverride: pasteAutomaticallyOverride
                )
            }
        )
    }

    private func chooseItem(
        at index: Int,
        removeFormatting: Bool = false,
        pasteAutomaticallyOverride: Bool? = nil
    ) -> Bool {
        guard viewModel.item(at: index) != nil else {
            return false
        }

        viewModel.selectIndex(index, scroll: false)
        ClipboardPanelSelectionCoordinator.chooseAfterDismiss(
            dismiss: { [weak self] in
                self?.hide()
            },
            choose: { [weak self] in
                self?.viewModel.chooseSelected(
                    removeFormatting: removeFormatting,
                    pasteAutomaticallyOverride: pasteAutomaticallyOverride
                )
            }
        )
        return true
    }

    private func hideIfLocalClickIsOutsidePanel(_ event: NSEvent) {
        guard event.window !== self else {
            return
        }

        hide()
    }
}
