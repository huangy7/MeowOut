import Cocoa
import SwiftUI

private final class FundPanelVisualEffectView: NSVisualEffectView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
public final class FundPanelController: NSPanel {
    public static let shared = FundPanelController()

    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var appState: AppState?

    public let viewModel: FundPanelViewModel

    private init() {
        viewModel = FundPanelViewModel()

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 460),
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

        let visualEffect = FundPanelVisualEffectView()
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
        Task { await viewModel.refresh() }
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
                if event.keyCode == 53 { // Escape
                    self.hide()
                    return nil
                }
                return event
            case .leftMouseDown, .rightMouseDown:
                if event.window !== self {
                    self.hide()
                }
                return event
            default:
                return event
            }
        }
    }

    private func makeHostingView() -> NSHostingView<FundPanelView> {
        NSHostingView(
            rootView: FundPanelView(
                viewModel: viewModel,
                appState: appState,
                language: appState?.language ?? .system
            )
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
}
