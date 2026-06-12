import AppKit
import Foundation
import SwiftUI

public enum QuickToolActionBehavior: Equatable {
    case launch
    case toggle
}

public enum QuickToolPostExecutionBehavior: Equatable {
    case closeImmediately
    case showFeedbackThenClose
}

public struct QuickToolActionState: Equatable {
    public var isActive: Bool
    public var subtitle: String

    public init(isActive: Bool, subtitle: String) {
        self.isActive = isActive
        self.subtitle = subtitle
    }
}

public struct QuickToolActionDescriptor {
    public var id: String
    public var displayName: String
    public var iconText: String?
    public var appPath: String?
    public var behavior: QuickToolActionBehavior
    public var state: QuickToolActionState?
    public var postExecutionBehavior: QuickToolPostExecutionBehavior
    public var execute: @MainActor () -> Void
}

@MainActor
public enum QuickToolActionResolver {
    public static func descriptor(for tool: QuickTool, appState: AppState) -> QuickToolActionDescriptor {
        switch tool {
        case .builtIn(let type):
            return builtInDescriptor(for: type, appState: appState)
        case .appShortcut(let id, let name, let path, let bookmark):
            var finalName = name
            if let components = FileManager.default.componentsToDisplay(forPath: path), let localizedName = components.last {
                finalName = localizedName
            }
            
            return QuickToolActionDescriptor(
                id: id.uuidString,
                displayName: finalName,
                iconText: nil,
                appPath: path,
                behavior: .launch,
                state: nil,
                postExecutionBehavior: .closeImmediately,
                execute: {
                    launchApp(path: path, bookmark: bookmark)
                }
            )
        }
    }

    private static func builtInDescriptor(for type: BuiltInToolType, appState: AppState) -> QuickToolActionDescriptor {
        let language = appState.language
        switch type {
        case .keepAwake:
            return toggleDescriptor(
                type: type,
                isActive: appState.isKeepingAwake,
                appState: appState,
                execute: { appState.toggleKeepAwake() }
            )
        case .keyboardCleaning:
            return toggleDescriptor(
                type: type,
                isActive: appState.isKeyboardCleaningActive,
                appState: appState,
                execute: { appState.toggleKeyboardCleaning() }
            )
        case .screenCleaning:
            return toggleDescriptor(
                type: type,
                isActive: appState.isScreenCleaningActive,
                appState: appState,
                execute: { appState.toggleScreenCleaning() }
            )
        case .memosQuickCapture:
            return launchDescriptor(type: type, language: language) {
                NotificationCenter.default.post(name: .toggleQuickMemoPanel, object: nil)
            }
        case .memosOpenBrowser:
            return launchDescriptor(type: type, language: language) {
                NotificationCenter.default.post(name: .toggleMemosBrowserWindow, object: nil)
            }
        case .breathing:
            return launchDescriptor(type: type, language: language) {
                NotificationCenter.default.post(name: NSNotification.Name("OpenBreathingWindow"), object: nil)
            }
        case .toolbox2FA:
            return launchDescriptor(type: type, language: language) {
                NotificationCenter.default.post(name: NSNotification.Name("OpenMeow2FAWindow"), object: nil)
            }
        }
    }

    private static func toggleDescriptor(
        type: BuiltInToolType,
        isActive: Bool,
        appState: AppState,
        execute: @escaping @MainActor () -> Void
    ) -> QuickToolActionDescriptor {
        QuickToolActionDescriptor(
            id: type.rawValue,
            displayName: type.localizedName(language: appState.language),
            iconText: type.icon,
            appPath: nil,
            behavior: .toggle,
            state: QuickToolActionState(
                isActive: isActive,
                subtitle: I18n.localized(isActive ? "tile_active" : "tile_inactive", language: appState.language)
            ),
            postExecutionBehavior: .showFeedbackThenClose,
            execute: execute
        )
    }

    private static func launchDescriptor(
        type: BuiltInToolType,
        language: AppState.AppLanguage,
        execute: @escaping @MainActor () -> Void
    ) -> QuickToolActionDescriptor {
        QuickToolActionDescriptor(
            id: type.rawValue,
            displayName: type.localizedName(language: language),
            iconText: type.icon,
            appPath: nil,
            behavior: .launch,
            state: nil,
            postExecutionBehavior: .closeImmediately,
            execute: execute
        )
    }

    private static func launchApp(path: String, bookmark: Data?) {
        var urlToLaunch = URL(fileURLWithPath: path)
        var accessed = false
        var resolvedUrl: URL?

        if let bookmark {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                accessed = resolved.startAccessingSecurityScopedResource()
                urlToLaunch = resolved
                resolvedUrl = resolved
            }
        }

        NSWorkspace.shared.openApplication(at: urlToLaunch, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if accessed {
                resolvedUrl?.stopAccessingSecurityScopedResource()
            }
            if let error {
                print("Failed to launch app: \(error.localizedDescription)")
            }
        }
    }
}
