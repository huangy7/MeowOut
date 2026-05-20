import AppKit
import Foundation
import Observation

/// 自动更新状态枚举
enum UpdateStatus: Equatable {
    case idle
    case checking
    case available(version: String, notes: String, url: URL)
    case downloading(progress: Double)
    case readyToInstall(version: String, dmgPath: String)
    case error(String)

    var hasPendingUpdate: Bool {
        switch self {
        case .available, .readyToInstall:
            return true
        case .idle, .checking, .downloading, .error:
            return false
        }
    }

    var pendingVersion: String? {
        switch self {
        case .available(let version, _, _), .readyToInstall(let version, _):
            return version
        case .idle, .checking, .downloading, .error:
            return nil
        }
    }
}

private struct AvailableUpdate {
    let notes: String
    let url: URL
}

/// GitHub Release API 自动更新检查器。
/// 结合了 HermesPet 的轻量安装脚本与 AppUpdater 的稳健进度追踪逻辑。
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    // MARK: - State
    
    private(set) var status: UpdateStatus = .idle
    private(set) var lastCheckedAt: Date?
    let currentVersion: String
    private var cachedAvailableUpdate: AvailableUpdate?

    // MARK: - Configuration
    
    private static let owner = "huangy7"
    private static let repo = "MeowOut"
    private static let checkInterval: TimeInterval = 24 * 60 * 60
    nonisolated static let installerScriptURL = URL(fileURLWithPath: "/tmp/meowout-upgrade.sh")
    private var periodicTask: Task<Void, Never>?

    private init() {
        self.currentVersion = Bundle.main.appVersion
    }

    var hasPendingUpdate: Bool {
        status.hasPendingUpdate
    }

    // MARK: - API

    func start() {
        periodicTask?.cancel()
        periodicTask = Task { @MainActor [weak self] in
            // 启动 60s 后首次检查，避开系统启动高峰
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            await self?.check(silently: true)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.checkInterval * 1_000_000_000))
                if Task.isCancelled { return }
                await self?.check(silently: true)
            }
        }
    }

    func check(silently: Bool = false) async {
        // 只有在空闲、已发现更新或出错时才允许重新检查
        switch status {
        case .idle, .available, .error: break
        default: return
        }
        
        status = .checking
        lastCheckedAt = Date()
        
        let urlString = "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/releases/latest"
        guard let url = URL(string: urlString) else {
            status = .error("Invalid URL")
            return
        }

        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("MeowOut/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                if !silently { status = .error("GitHub API Error: \(code)") }
                else { status = .idle }
                return
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                status = .error("Failed to parse release info")
                return
            }
            
            let latestVersion = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let notes = (json["body"] as? String) ?? ""
            
            // 语义版本比对
            if Self.compare(latestVersion, isNewerThan: currentVersion) {
                // 寻找 DMG 资产
                var downloadURL: URL?
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String, name.hasSuffix(".dmg"),
                           let urlStr = asset["browser_download_url"] as? String {
                            downloadURL = URL(string: urlStr)
                            break
                        }
                    }
                }
                
                if let finalURL = downloadURL {
                    cachedAvailableUpdate = AvailableUpdate(notes: notes, url: finalURL)
                    status = .available(version: latestVersion, notes: notes, url: finalURL)
                } else {
                    status = .error("Release assets missing DMG")
                }
            } else {
                cachedAvailableUpdate = nil
                status = .idle // 已是最新
            }
        } catch {
            if !silently { status = .error(error.localizedDescription) }
            else { status = .idle }
        }
    }

    func downloadAndInstall(language: AppState.AppLanguage) async {
        switch status {
        case let .available(version, _, url):
            await startDownload(version: version, url: url, language: language)
        case let .readyToInstall(version, dmgPath):
            if Self.isDownloadedDMGAvailable(at: dmgPath) {
                await presentInstallAlert(language: language)
            } else if let destination = cachedAvailableUpdate {
                status = .available(version: version, notes: destination.notes, url: destination.url)
                await startDownload(version: version, url: destination.url, language: language)
            } else {
                status = .error("Downloaded update is missing. Please check for updates again.")
            }
        default:
            return
        }
    }

    private func startDownload(version: String, url: URL, language: AppState.AppLanguage) async {
        status = .downloading(progress: 0)
        
        let destination = Self.downloadDestination(for: version)
        
        try? FileManager.default.removeItem(at: destination)

        do {
            let delegate = DownloadDelegate { [weak self] progress in
                Task { @MainActor in
                    if case .downloading = self?.status {
                        self?.status = .downloading(progress: progress)
                    }
                }
            }
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let (tempURL, response) = try await session.download(from: url)
            session.finishTasksAndInvalidate()
            
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                status = .error("Download failed: HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return
            }
            
            try FileManager.default.moveItem(at: tempURL, to: destination)
            status = .readyToInstall(version: version, dmgPath: destination.path)
            
            // 自动弹框提示安装
            await presentInstallAlert(language: language)
        } catch {
            status = .error("Download failed: \(error.localizedDescription)")
        }
    }

    private func presentInstallAlert(language: AppState.AppLanguage) async {
        guard case let .readyToInstall(version, dmgPath) = status else { return }
        
        // Close any existing installer window
        UpdateInstallWindow.shared?.close()
        
        let window = UpdateInstallWindow(
            version: version,
            language: language,
            onConfirm: { [weak self] in
                Task {
                    await self?.executeInstall(dmgPath: dmgPath, language: language)
                }
            },
            onCancel: {
                // Cancelled
            }
        )
        
        UpdateInstallWindow.shared = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func executeInstall(dmgPath: String, language: AppState.AppLanguage) async {
        guard case let .readyToInstall(_, path) = status else { return }
        
        guard let volumePath = await Self.attachDMG(dmgPath: path) else {
            status = .error("Failed to mount DMG")
            return
        }
        
        guard let newAppPath = findAppInVolume(volumePath) else {
            NSWorkspace.shared.open(URL(fileURLWithPath: volumePath))
            status = .error("Could not find .app in DMG")
            return
        }
        
        let oldAppPath = Bundle.main.bundlePath
        if let scriptPath = writeInstallScript(oldApp: oldAppPath, newApp: newAppPath, volume: volumePath, dmg: path) {
            launchInstaller(scriptPath: scriptPath)
            NSApp.terminate(nil)
        } else {
            status = .error("Failed to write install script")
        }
    }

    private func fallbackToManual(volumePath: String, language: AppState.AppLanguage) {
        NSWorkspace.shared.open(URL(fileURLWithPath: volumePath))
        let alert = NSAlert()
        alert.messageText = I18n.localized("update_manual_title", language: language)
        alert.informativeText = I18n.localized("update_manual_body", language: language)
        alert.runModal()
    }

    // MARK: - Helpers

    nonisolated static func downloadDestination(for version: String) -> URL {
        URL(fileURLWithPath: "/tmp/MeowOut-Update-\(version).dmg")
    }

    nonisolated static func isDownloadedDMGAvailable(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    private static func attachDMG(dmgPath: String) async -> String? {
        await Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            proc.arguments = ["attach", dmgPath, "-nobrowse", "-noverify", "-noautoopen"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            try? proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            for line in output.split(separator: "\n") {
                if let range = line.range(of: "/Volumes/") {
                    return String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
                }
            }
            return nil
        }.value
    }

    private func findAppInVolume(_ volumePath: String) -> String? {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: volumePath)) ?? []
        let currentName = (Bundle.main.bundlePath as NSString).lastPathComponent
        if items.contains(currentName) {
            return (volumePath as NSString).appendingPathComponent(currentName)
        }
        return items.first(where: { $0.hasSuffix(".app") }).map { (volumePath as NSString).appendingPathComponent($0) }
    }

    private func writeInstallScript(oldApp: String, newApp: String, volume: String, dmg: String) -> String? {
        let pid = ProcessInfo.processInfo.processIdentifier
        let logFile = "/tmp/meowout-update.log"
        
        let script = """
        #!/bin/bash
        # MeowOut Update Installer Script
        # Optimized for seamless app replacement and cleanup.

        LOG="\(logFile)"
        echo "--- Update started at $(date) ---" > "$LOG"

        # 1. Wait for the main MeowOut process to terminate
        echo "Waiting for PID \(pid) to exit..." >> "$LOG"
        for i in $(seq 1 60); do
          if ! kill -0 "\(pid)" 2>/dev/null; then
            echo "Main process exited." >> "$LOG"
            break
          fi
          sleep 0.2
        done
        sleep 0.5

        # 2. Atomic replacement using a staging directory
        STAGING="\(oldApp).new"
        echo "Staging new version at $STAGING" >> "$LOG"
        rm -rf "$STAGING"

        if /usr/bin/ditto "\(newApp)" "$STAGING"; then
          echo "Ditto successful. Swapping versions..." >> "$LOG"
          rm -rf "\(oldApp)"
          mv "$STAGING" "\(oldApp)"
          
          # Remove Apple's quarantine attribute to allow the app to run without 'damaged' warnings
          echo "Clearing quarantine attributes..." >> "$LOG"
          /usr/bin/xattr -cr "\(oldApp)" 2>/dev/null || true
        else
          echo "ERROR: Failed to copy new version to staging area." >> "$LOG"
          rm -rf "$STAGING"
          # Fallback: Don't delete the old app if the new one isn't ready
        fi

        # 3. Cleanup: Detach DMG and remove the downloaded file
        echo "Cleaning up resources..." >> "$LOG"
        /usr/bin/hdiutil detach "\(volume)" -quiet -force 2>/dev/null || true
        rm -f "\(dmg)"

        # 4. Relaunch the new version
        echo "Relaunching MeowOut..." >> "$LOG"
        /usr/bin/open "\(oldApp)"

        # 5. Self-destruct
        echo "Update completed successfully. Self-destructing script." >> "$LOG"
        rm -f "$0"
        """
        let scriptURL = Self.installerScriptURL
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            return scriptURL.path
        } catch {
            return nil
        }
    }

    private func launchInstaller(scriptPath: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", "nohup /bin/bash \"\(scriptPath)\" >/dev/null 2>&1 &"]
        try? task.run()
    }

    static func compare(_ a: String, isNewerThan b: String) -> Bool {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(aParts.count, bParts.count) {
            let ai = i < aParts.count ? aParts[i] : 0
            let bi = i < bParts.count ? bParts[i] : 0
            if ai != bi { return ai > bi }
        }
        return false
    }
}

// MARK: - Supporting Delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?

    init(progress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = progress
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response else {
            continuation?.resume(throwing: NSError(domain: "UpdateChecker", code: -1))
            return
        }
        // 必须先移动文件，因为此 location 是临时的，session 结束后会被删
        let tempTarget = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dmg")
        try? FileManager.default.moveItem(at: location, to: tempTarget)
        continuation?.resume(returning: (tempTarget, response))
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            continuation?.resume(throwing: error)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }
    
    func setContinuation(_ continuation: CheckedContinuation<(URL, URLResponse), Error>) {
        self.continuation = continuation
    }
}

private extension URLSession {
    func download(from url: URL) async throws -> (URL, URLResponse) {
        guard let delegate = self.delegate as? DownloadDelegate else {
            throw NSError(domain: "UpdateChecker", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid delegate"])
        }
        return try await withCheckedThrowingContinuation { continuation in
            delegate.setContinuation(continuation)
            let task = self.downloadTask(with: url)
            task.resume()
        }
    }
}
