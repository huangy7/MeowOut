import SwiftUI
import AppKit

/// 托盘左键面板的内容视图（原 MenuBarExtra 的 menuContent），
/// 现由 MenuBarController 的 NSPopover 承载。
struct MenuPanelView: View {
    @Bindable var appState: AppState
    @AppStorage("isQuickToolsExpanded") private var isQuickToolsExpanded = false
    @AppStorage("showSystemMonitorCard") private var showSystemMonitorCard = true
    @State private var isHoveredToggle = false
    @ObservedObject private var clamshell = ClamshellManager.shared

    var body: some View {
        VStack(spacing: 0) {
            menuContent
        }
        .frame(width: 280)
        .background {
            MenuVisualEffectView()
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        VStack(spacing: 8) {
            // Card 1: Dashboard & Pause Controls
            if appState.enableRestReminder {
                MenuDashboardCard(appState: appState)
            }

            // Card 1.5: System Monitor
            if showSystemMonitorCard {
                SystemMonitorCardView(appState: appState)
            }

            // Card 2: Tools & Shortcuts
            if appState.showQuickToolsCard {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        let topTools = Array(appState.quickTools.prefix(2))
                        if topTools.isEmpty {
                            Text(I18n.localized("menu_shortcuts_empty", language: appState.language))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            ForEach(topTools) { tool in
                                renderToolTile(tool)
                            }
                            if topTools.count < 2 {
                                Spacer()
                            }
                        }
                    }

                    if appState.quickTools.count > 2 {
                        if isQuickToolsExpanded {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                                let remainingTools = Array(appState.quickTools.dropFirst(2))
                                ForEach(remainingTools) { tool in
                                    renderSmallToolTile(tool)
                                }
                            }
                        }

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isQuickToolsExpanded.toggle()
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Text(isQuickToolsExpanded ? "^ 收起" : "v 展开快捷应用")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.primary.opacity(0.6))
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(isHoveredToggle ? 0.08 : 0.04))
                            .cornerRadius(6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { h in isHoveredToggle = h }
                    }
                }
                .padding(12)
                .menuCardStyle()
            }


            // Card 4: System Actions
            VStack(spacing: 0) {
                MenuRowButton(
                    title: I18n.localized("menu_settings", language: appState.language),
                    icon: "⚙️",
                    iconColor: .secondary,
                    hasBadge: UpdateChecker.shared.hasPendingUpdate
                ) {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenSettingsWindow"), object: nil)
                }

                Divider().background(Color.primary.opacity(0.05)).padding(.horizontal, 14)

                MenuRowButton(
                    title: I18n.localized("menu_quit", language: appState.language),
                    icon: "⏻",
                    iconColor: .red,
                    showChevron: false
                ) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .menuCardStyle()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func renderToolTile(_ tool: QuickTool) -> some View {
        let descriptor = QuickToolActionResolver.descriptor(for: tool, appState: appState)
        let launchSubtitle = I18n.localized("menu_shortcuts_launch", language: appState.language)

        let isClamshell = (descriptor.id == BuiltInToolType.keepAwake.rawValue) && ClamshellManager.shared.isEnabledGlobally && (descriptor.state?.isActive == true)

        ControlTileButton(
            title: descriptor.displayName,
            subtitleActive: descriptor.state?.subtitle ?? launchSubtitle,
            subtitleInactive: descriptor.state?.subtitle ?? launchSubtitle,
            iconEmoji: descriptor.iconText ?? "🚀",
            isActive: descriptor.state?.isActive ?? false,
            isClamshellKeepAwake: isClamshell,
            action: {
                if descriptor.behavior == .launch || descriptor.id != BuiltInToolType.keepAwake.rawValue {
                    MenuBarController.shared.closePopover()
                }
                descriptor.execute()
            }
        )
    }

    @ViewBuilder
    private func renderSmallToolTile(_ tool: QuickTool) -> some View {
        let descriptor = QuickToolActionResolver.descriptor(for: tool, appState: appState)

        Button {
            MenuBarController.shared.closePopover()
            descriptor.execute()
        } label: {
            VStack(spacing: 4) {
                if let iconText = descriptor.iconText {
                    Text(iconText).font(.system(size: 18))
                } else if let path = descriptor.appPath {
                    AppIconView(path: path)
                }
                Text(descriptor.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(10)
            .overlay(alignment: .topTrailing) {
                if descriptor.state?.isActive == true {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .offset(x: -4, y: 4)
                }
            }
        }
        .buttonStyle(.plain)
        .help(descriptor.displayName)
    }
}

// MARK: - Component Views

struct QuickPauseButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            MenuBarController.shared.closePopover()
            action()
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(isHovered ? Color.orange.opacity(0.12) : Color.primary.opacity(0.06))
                .foregroundColor(isHovered ? .orange : .primary.opacity(0.8))
                .cornerRadius(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct ControlTileButton: View {
    let title: String
    let subtitleActive: String
    let subtitleInactive: String
    let iconEmoji: String
    let isActive: Bool
    var isClamshellKeepAwake: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .center, spacing: 6) {
                Text(iconEmoji)
                    .font(.system(size: 24))
                    .frame(height: 26)

                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isActive ? .white : .primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 72)
            .background {
                if isActive {
                    LinearGradient(
                        colors: [Color(red: 255/255, green: 159/255, blue: 67/255), Color(red: 255/255, green: 140/255, blue: 26/255)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    Color.primary.opacity(isHovered ? 0.08 : 0.04)
                }
            }
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isActive ? Color.orange.opacity(0.2) : Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .overlay(alignment: .topTrailing) {
                if isClamshellKeepAwake {
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 6, height: 6)
                        .shadow(color: Color.black.opacity(0.15), radius: 1, x: 0, y: 1)
                        .offset(x: -8, y: 8)
                        .help(I18n.localized("power_clamshell_title", language: AppState().language))
                }
            }
            .shadow(color: isActive ? Color.orange.opacity(0.2) : Color.black.opacity(0.04), radius: isActive ? 5 : 3, x: 0, y: isActive ? 2 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct MenuRowButton: View {
    let title: String
    let icon: String
    var iconColor: Color = .primary.opacity(0.8)
    var hasBadge: Bool = false
    var showChevron: Bool = true
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            MenuBarController.shared.closePopover()
            action()
        } label: {
            HStack(spacing: 8) {
                Text(icon)
                    .font(.system(size: 13))
                    .frame(width: 20, alignment: .center)
                    .foregroundColor(iconColor)

                Text(title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.primary)

                if hasBadge {
                    UpdateBadge()
                }

                Spacer()

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.primary.opacity(0.15))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8.5)
            .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel(hasBadge
                            ? "\(title), \(I18n.localized("settings_update_badge_a11y"))"
                            : title)
    }
}

struct MenuDashboardCard: View {
    @Bindable var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                // Left Column: Goal
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("🎯")
                            .font(.system(size: 13))
                        Text(I18n.localized("stats_todays_goal", language: appState.language))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Button(action: {
                            MenuBarController.shared.closePopover()
                            NSApp.activate(ignoringOtherApps: true)
                            (NSApp.delegate as? AppDelegate)?.tryStartEngine()
                            appState.settingsNavigationTarget = .statistics
                            NotificationCenter.default.post(name: NSNotification.Name("OpenSettingsWindow"), object: nil)
                        }) {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .help(I18n.localized("settings_tab_statistics", language: appState.language))
                    }

                    let goalProgress = min(1.0, appState.totalWorkToday / (Double(appState.dailyWorkGoal) * 3600))
                    HStack(alignment: .center, spacing: 10) {
                        CapsuleProgressView(value: goalProgress)

                        Text("\(String(format: "%.1f", appState.totalWorkToday / 3600)) / \(appState.dailyWorkGoal).0 h")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 12)

                Divider()
                    .frame(height: 40)
                    .background(Color.primary.opacity(0.05))

                // Right Column: Session
                VStack(alignment: .center, spacing: 0) {
                    let sessionProgress = min(1.0, appState.workElapsed / appState.maxWorkTime)
                    CircularProgressView(
                        value: sessionProgress,
                        text: "\(Int(appState.workElapsed / 60))m"
                    )
                }
                .frame(width: 56)
                .padding(.leading, 12)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Water Row
            HStack(spacing: 6) {
                Text("💧")
                    .font(.system(size: 13))
                Text(I18n.localized("water_today_label", language: appState.language))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                Text("\(appState.todayWaterCups)/\(appState.dailyWaterGoal)")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.blue)
                Button(action: {
                    appState.todayWaterCups += 1
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            Divider()
                .background(Color.primary.opacity(0.05))
                .padding(.horizontal, 14)

            // Pause Row
            if appState.currentState == .paused {
                HStack(spacing: 8) {
                    Text("⏸")
                        .font(.system(size: 12))
                    Text(I18n.localizedFormat("menu_paused_label", language: appState.language, Int64(appState.pauseRemaining / 60)))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.primary)
                    Spacer()
                    Button {
                        appState.currentState = .working
                        appState.pauseRemaining = 0
                        MenuBarController.shared.closePopover()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8, weight: .bold))
                            Text(I18n.localized("menu_resume", language: appState.language))
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            } else {
                HStack(spacing: 8) {
                    Text("⏸")
                        .font(.system(size: 12))
                    Text(I18n.localized("menu_pause", language: appState.language))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.primary)
                    Spacer()
                    HStack(spacing: 4) {
                        QuickPauseButton(title: "15m") { pause(minutes: 15) }
                        QuickPauseButton(title: "30m") { pause(minutes: 30) }
                        QuickPauseButton(title: "1h") { pause(minutes: 60) }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .onAppear {
            appState.checkAndResetWaterIfNewDay()
        }
        .menuCardStyle()
    }

    private func pause(minutes: Int) {
        appState.pauseRemaining = TimeInterval(minutes * 60)
        appState.currentState = .paused
    }
}

// MARK: - Internal Progress Components

struct CapsuleProgressView: View {
    var value: Double // 0.0 to 1.0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 7)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color(red: 255/255, green: 173/255, blue: 51/255)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(7, geometry.size.width * value), height: 7)
                    .shadow(color: .orange.opacity(0.3), radius: 3, x: 0, y: 0)
            }
        }
        .frame(height: 7)
    }
}

struct CircularProgressView: View {
    var value: Double // 0.0 to 1.0
    var text: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 3.5)

            Circle()
                .trim(from: 0, to: value)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text(text)
                .font(.system(size: 10, weight: .bold))
        }
        .frame(width: 44, height: 44)
    }
}

struct MenuCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark

        return content
            .background(isDark ? Color.white.opacity(0.09) : Color.white.opacity(0.5))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(isDark ? 0.12 : 0.35), lineWidth: 0.5)
            )
    }
}

extension View {
    func menuCardStyle() -> some View {
        modifier(MenuCardModifier())
    }
}

struct MenuVisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .popover
        DispatchQueue.main.async {
            if let window = view.window {
                window.isOpaque = false
                window.backgroundColor = .clear
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                window.isOpaque = false
                window.backgroundColor = .clear
            }
        }
    }

    /// 外观模式对应的 NSAppearance（nil = 跟随系统）
    static func nsAppearance(for mode: AppState.AppearanceMode) -> NSAppearance? {
        switch mode {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .system: return nil
        }
    }
}

struct AppIconView: View {
    let path: String
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon = icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 24, height: 24)
        .onAppear {
            DispatchQueue.global(qos: .userInitiated).async {
                let fetchedIcon = NSWorkspace.shared.icon(forFile: path)
                DispatchQueue.main.async {
                    self.icon = fetchedIcon
                }
            }
        }
    }
}
