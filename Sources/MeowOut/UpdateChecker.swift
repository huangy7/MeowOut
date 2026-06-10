import AppKit
import Foundation
import Observation
import Darwin

nonisolated func logDebug(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    let dateString = formatter.string(from: Date())
    let logLine = "[\(dateString)] \(message)\n"
    if let data = logLine.data(using: .utf8) {
        let fileURL = URL(fileURLWithPath: "/tmp/meowout-update-debug.log")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? fileHandle.close() }
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
            }
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
    NSLog("UpdaterDebug: %@", message)
}

/// 自动更新错误类型
enum UpdateError: Equatable {
    case invalidURL
    case apiError(statusCode: Int)
    case parseFailed
    case assetsMissingDMG
    case requestFailed(description: String)
    case updateMissing
    case downloadFailedHTTP(statusCode: Int)
    case downloadFailed(description: String)
    case mountFailed
    case appNotFound
    case scriptWriteFailed

    func localizedDescription(language: AppState.AppLanguage) -> String {
        switch self {
        case .invalidURL:
            return I18n.localized("update_error_invalid_url", language: language)
        case .apiError(let code):
            return I18n.localizedFormat("update_error_api_failed", language: language, Int64(code))
        case .parseFailed:
            return I18n.localized("update_error_parse_failed", language: language)
        case .assetsMissingDMG:
            return I18n.localized("update_error_assets_missing", language: language)
        case .requestFailed(let desc):
            return I18n.localizedFormat("update_error_request_failed", language: language, desc)
        case .updateMissing:
            return I18n.localized("update_error_update_missing", language: language)
        case .downloadFailedHTTP(let code):
            return I18n.localizedFormat("update_error_download_http", language: language, Int64(code))
        case .downloadFailed(let desc):
            return I18n.localizedFormat("update_error_download_failed", language: language, desc)
        case .mountFailed:
            return I18n.localized("update_error_mount_failed", language: language)
        case .appNotFound:
            return I18n.localized("update_error_app_missing", language: language)
        case .scriptWriteFailed:
            return I18n.localized("update_error_script_write", language: language)
        }
    }
}

/// 自动更新状态枚举
enum UpdateStatus: Equatable {
    case idle
    case checking
    case available(version: String, notes: String, url: URL)
    case downloading(progress: Double)
    case readyToInstall(version: String, dmgPath: String)
    case error(UpdateError)

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
/// 结合了轻量安装脚本与稳健的进度追踪逻辑。
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    // MARK: - State
    
    private(set) var status: UpdateStatus = .idle
    private(set) var lastCheckedAt: Date?
    let currentVersion: String
    private var cachedAvailableUpdate: AvailableUpdate?
    private var installTask: Task<Void, Never>?

    // MARK: - Configuration
    
    private static let owner = "huangy7"
    private static let repo = "MeowOut"
    private static let checkInterval: TimeInterval = 24 * 60 * 60
    nonisolated static var installerScriptURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return dir
            .appendingPathComponent("MeowOut", isDirectory: true)
            .appendingPathComponent("update-installer.sh")
    }
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
        logDebug("check called, silently: \(silently), current status: \(status)")
        // 只有在空闲、已发现更新或出错时才允许重新检查
        switch status {
        case .idle, .available, .error: break
        default: return
        }
        
        status = .checking
        lastCheckedAt = Date()
        
        let urlString = "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/releases/latest"
        logDebug("checking updates at: \(urlString)")
        guard let url = URL(string: urlString) else {
            logDebug("check failed - invalid URL")
            status = .error(.invalidURL)
            return
        }

        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("MeowOut/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                logDebug("check HTTP error: \(code)")
                if !silently { status = .error(.apiError(statusCode: code)) }
                else { status = .idle }
                return
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                logDebug("check failed - json parse failed")
                status = .error(.parseFailed)
                return
            }
            
            let latestVersion = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let notes = (json["body"] as? String) ?? ""
            logDebug("parsed tag version: \(latestVersion) (current is \(currentVersion))")
            
            // 语义版本比对
            if Self.compare(latestVersion, isNewerThan: currentVersion) {
                let downloadURL = Self.selectDMGAssetURL(
                    from: json["assets"] as? [[String: Any]] ?? [],
                    preferredArchitecture: Self.currentArchitecture
                )
                
                if let finalURL = downloadURL {
                    logDebug("found DMG download URL: \(finalURL.absoluteString)")
                    cachedAvailableUpdate = AvailableUpdate(notes: notes, url: finalURL)
                    status = .available(version: latestVersion, notes: notes, url: finalURL)
                } else {
                    logDebug("check failed - DMG asset missing")
                    status = .error(.assetsMissingDMG)
                }
            } else {
                logDebug("latest version \(latestVersion) is not newer than current \(currentVersion)")
                cachedAvailableUpdate = nil
                status = .idle // 已是最新
            }
        } catch {
            logDebug("check failed with error: \(error.localizedDescription)")
            if !silently { status = .error(.requestFailed(description: error.localizedDescription)) }
            else { status = .idle }
        }
    }

    func downloadAndInstall(language: AppState.AppLanguage) async {
        logDebug("downloadAndInstall called, current status: \(status)")
        switch status {
        case let .available(version, _, url):
            let dest = Self.downloadDestination(for: version)
            if Self.isDownloadedDMGAvailable(at: dest.path) {
                logDebug("Local DMG already exists at \(dest.path), skipping download.")
                status = .readyToInstall(version: version, dmgPath: dest.path)
                await presentInstallAlert(language: language)
            } else {
                await startDownload(version: version, url: url, language: language)
            }
        case let .readyToInstall(version, dmgPath):
            if Self.isDownloadedDMGAvailable(at: dmgPath) {
                await presentInstallAlert(language: language)
            } else if let destination = cachedAvailableUpdate {
                status = .available(version: version, notes: destination.notes, url: destination.url)
                await startDownload(version: version, url: destination.url, language: language)
            } else {
                status = .error(.updateMissing)
            }
        default:
            return
        }
    }

    private func startDownload(version: String, url: URL, language: AppState.AppLanguage) async {
        logDebug("startDownload called, version: \(version), url: \(url)")
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
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                logDebug("startDownload HTTP status error: \(code)")
                status = .error(.downloadFailedHTTP(statusCode: code))
                return
            }
            
            let parentDir = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: tempURL, to: destination)
            logDebug("download successful. Moved to: \(destination.path)")
            status = .readyToInstall(version: version, dmgPath: destination.path)
            
            // 自动弹框提示安装
            await presentInstallAlert(language: language)
        } catch {
            logDebug("startDownload failed with error: \(error.localizedDescription)")
            status = .error(.downloadFailed(description: error.localizedDescription))
        }
    }

    private func presentInstallAlert(language: AppState.AppLanguage) async {
        logDebug("presentInstallAlert called, status is: \(status)")
        guard case let .readyToInstall(version, dmgPath) = status else {
            logDebug("presentInstallAlert aborted: status is not readyToInstall")
            return
        }
        // Close any existing installer window
        UpdateInstallWindow.shared?.close()
        
        logDebug("creating UpdateInstallWindow")
        let window = UpdateInstallWindow(
            version: version,
            language: language,
            onConfirm: {
                logDebug("UpdateInstallWindow: onConfirm triggered")
                UpdateChecker.shared.beginInstall(dmgPath: dmgPath, language: language)
            },
            onCancel: {
                logDebug("UpdateInstallWindow: onCancel triggered")
            }
        )
        
        UpdateInstallWindow.shared = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        logDebug("UpdateInstallWindow made key and ordered front")
    }

    private func beginInstall(dmgPath: String, language: AppState.AppLanguage) {
        logDebug("beginInstall called; creating retained install task")
        installTask?.cancel()
        installTask = Task { @MainActor [dmgPath, language] in
            logDebug("Install task entered MainActor")
            await UpdateChecker.shared.executeInstall(dmgPath: dmgPath, language: language)
        }
    }

    private func executeInstall(dmgPath: String, language: AppState.AppLanguage) async {
        logDebug("executeInstall started with dmgPath: \(dmgPath)")
        guard case let .readyToInstall(version, path) = status else {
            logDebug("executeInstall failed - status is not readyToInstall. Current status: \(status)")
            return
        }
        
        logDebug("Attaching DMG at \(path)")
        guard let volumePath = await Self.attachDMG(dmgPath: path) else {
            logDebug("executeInstall failed - attachDMG returned nil")
            status = .error(.mountFailed)
            return
        }
        
        logDebug("Mounted volume at \(volumePath). Finding app...")
        guard let newAppPath = findAppInVolume(volumePath) else {
            logDebug("executeInstall failed - findAppInVolume returned nil")
            fallbackToManual(volumePath: volumePath, language: language)
            status = .error(.appNotFound)
            return
        }
        
        let oldAppPath = Bundle.main.bundlePath
        let parentDir = (oldAppPath as NSString).deletingLastPathComponent
        logDebug("Found new app at \(newAppPath). Old app is \(oldAppPath), parent dir: \(parentDir)")
        guard FileManager.default.isWritableFile(atPath: parentDir) else {
            logDebug("executeInstall failed - parentDir \(parentDir) is not writable")
            fallbackToManual(volumePath: volumePath, language: language)
            status = .error(.mountFailed)
            return
        }
        
        logDebug("Writing install script...")
        if let scriptPath = writeInstallScript(oldApp: oldAppPath, newApp: newAppPath, volume: volumePath, dmg: path, expectedVersion: version) {
            logDebug("Script written to \(scriptPath). Launching installer...")
            launchInstaller(scriptPath: scriptPath)
            logDebug("Installer launched. Terminating application...")
            NSApp.terminate(nil)
        } else {
            logDebug("executeInstall failed - writeInstallScript returned nil")
            fallbackToManual(volumePath: volumePath, language: language)
            status = .error(.scriptWriteFailed)
        }
    }

    private func launchInstaller(scriptPath: String) {
        logDebug("launchInstaller called with scriptPath: \(scriptPath)")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", "nohup /bin/bash \(Self.shellSingleQuoted(scriptPath)) >/tmp/meowout-update.log 2>&1 &"]
        do {
            try task.run()
            task.waitUntilExit()   // Wait for the outer bash to spawn nohup process and exit
            logDebug("launchInstaller process run and wait completed successfully")
        } catch {
            logDebug("launchInstaller process run failed with error: \(error.localizedDescription)")
        }
    }

    nonisolated static func isDownloadedDMGAvailable(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    nonisolated static func downloadDestination(for version: String) -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return dir
            .appendingPathComponent("MeowOut", isDirectory: true)
            .appendingPathComponent("MeowOut-Update-\(version).dmg")
    }

    nonisolated static var currentArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    nonisolated static func selectDMGAssetURL(from assets: [[String: Any]], preferredArchitecture: String) -> URL? {
        let dmgAssets = assets.compactMap { asset -> (name: String, url: URL)? in
            guard let name = asset["name"] as? String,
                  name.lowercased().hasSuffix(".dmg"),
                  let urlString = asset["browser_download_url"] as? String,
                  let url = URL(string: urlString) else {
                return nil
            }
            return (name, url)
        }

        let preferredTokens: [String]
        if preferredArchitecture == "arm64" {
            preferredTokens = ["arm64", "apple silicon", "applesilicon", "aarch64"]
        } else {
            preferredTokens = ["x86_64", "x64", "intel", "amd64"]
        }

        if let matched = dmgAssets.first(where: { asset in
            let lowercasedName = asset.name.lowercased()
            return preferredTokens.contains(where: lowercasedName.contains)
        }) {
            return matched.url
        }

        return dmgAssets.first?.url
    }

    private static func attachDMG(dmgPath: String) async -> String? {
        logDebug("attachDMG starting for path: \(dmgPath)")
        return await Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            proc.arguments = ["attach", dmgPath, "-nobrowse", "-noverify", "-noautoopen"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            let errPipe = Pipe()
            proc.standardError = errPipe
            do {
                try proc.run()
            } catch {
                logDebug("hdiutil run failed with error: \(error.localizedDescription)")
                return nil
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            let errOutput = String(data: errData, encoding: .utf8) ?? ""
            logDebug("hdiutil exit status: \(proc.terminationStatus)")
            if !output.isEmpty {
                logDebug("hdiutil stdout: \(output)")
            }
            if !errOutput.isEmpty {
                logDebug("hdiutil stderr: \(errOutput)")
            }
            guard proc.terminationStatus == 0 else { return nil }
            for line in output.split(separator: "\n") {
                if let range = line.range(of: "/Volumes/") {
                    let volume = String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
                    logDebug("found volume mount path: \(volume)")
                    return volume
                }
            }
            logDebug("no volume path found in hdiutil output")
            return nil
        }.value
    }

    private func findAppInVolume(_ volumePath: String) -> String? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: volumePath) else { return nil }
        let currentName = (Bundle.main.bundlePath as NSString).lastPathComponent
        if items.contains(currentName) {
            return (volumePath as NSString).appendingPathComponent(currentName)
        }
        if let appName = items.first(where: { $0.hasSuffix(".app") }) {
            return (volumePath as NSString).appendingPathComponent(appName)
        }
        return nil
    }

    private func fallbackToManual(volumePath: String, language: AppState.AppLanguage) {
        NSWorkspace.shared.open(URL(fileURLWithPath: volumePath))
        let alert = NSAlert()
        alert.messageText = I18n.localized("update_manual_title", language: language)
        alert.informativeText = I18n.localized("update_manual_body", language: language)
        alert.alertStyle = .informational
        alert.addButton(withTitle: I18n.localized("update_manual_confirm", language: language))
        alert.runModal()
    }

    nonisolated static func installScriptContent(
        oldApp: String,
        newApp: String,
        volume: String,
        dmg: String,
        parentPID: Int32,
        expectedVersion: String
    ) -> String {
        return """
        #!/bin/bash
        OLD_APP=\(shellSingleQuoted(oldApp))
        NEW_APP=\(shellSingleQuoted(newApp))
        VOLUME=\(shellSingleQuoted(volume))
        DMG=\(shellSingleQuoted(dmg))
        PARENT_PID=\(parentPID)
        EXPECTED_VERSION=\(shellSingleQuoted(expectedVersion))
        STAGING="${OLD_APP}.new"
        BACKUP="${OLD_APP}.old-update"

        fail() {
          echo "ERROR: $1"
          /bin/rm -rf "$STAGING" 2>/dev/null || true
          if [ -d "$BACKUP" ] && [ ! -d "$OLD_APP" ]; then
            /bin/mv "$BACKUP" "$OLD_APP" 2>/dev/null || true
          fi
          /usr/bin/hdiutil detach "$VOLUME" -quiet -force 2>/dev/null || true
          exit 1
        }

        echo "--- Update started at $(date) ---"
        echo "Waiting for PID $PARENT_PID to exit..."

        for i in $(seq 1 60); do
          kill -0 "$PARENT_PID" 2>/dev/null || break
          sleep 0.2
        done

        if kill -0 "$PARENT_PID" 2>/dev/null; then
          fail "Parent process still running after timeout"
        fi
        echo "Main process exited."

        sleep 0.5

        echo "Staging new version at $STAGING"
        /bin/rm -rf "$STAGING" || fail "Failed to clear staging app"
        /bin/rm -rf "$BACKUP" || fail "Failed to clear backup app"

        /usr/bin/ditto "$NEW_APP" "$STAGING" || fail "Failed to copy new app to staging"

        STAGED_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$STAGING/Contents/Info.plist" 2>/dev/null) || fail "Failed to read staged app version"
        echo "Staged version: $STAGED_VERSION"
        if [ "$STAGED_VERSION" != "$EXPECTED_VERSION" ]; then
          fail "Staged app version $STAGED_VERSION does not match expected $EXPECTED_VERSION"
        fi

        echo "Swapping versions..."
        /bin/mv "$OLD_APP" "$BACKUP" || fail "Failed to move old app to backup"
        /bin/mv "$STAGING" "$OLD_APP" || fail "Failed to move staged app into place"

        UPDATED_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$OLD_APP/Contents/Info.plist" 2>/dev/null) || fail "Failed to read installed app version"
        echo "Installed version: $UPDATED_VERSION"
        if [ "$UPDATED_VERSION" != "$EXPECTED_VERSION" ]; then
          fail "Installed app version $UPDATED_VERSION does not match expected $EXPECTED_VERSION"
        fi

        echo "Clearing quarantine attributes..."
        /usr/bin/xattr -cr "$OLD_APP" 2>/dev/null || true
        /bin/rm -rf "$BACKUP" || true

        echo "Cleaning up resources..."
        /usr/bin/hdiutil detach "$VOLUME" -quiet -force 2>/dev/null || true
        /bin/rm -f "$DMG"

        echo "Relaunching MeowOut..."
        /usr/bin/open "$OLD_APP" || fail "Failed to relaunch app"

        echo "Update completed successfully. Self-destructing script."
        /bin/rm -f "$0"
        """
    }

    nonisolated static func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func writeInstallScript(oldApp: String, newApp: String, volume: String, dmg: String, expectedVersion: String) -> String? {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = Self.installScriptContent(
            oldApp: oldApp,
            newApp: newApp,
            volume: volume,
            dmg: dmg,
            parentPID: pid,
            expectedVersion: expectedVersion
        )
        
        let scriptURL = Self.installerScriptURL
        do {
            try FileManager.default.createDirectory(
                at: scriptURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            return scriptURL.path
        } catch {
            return nil
        }
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
