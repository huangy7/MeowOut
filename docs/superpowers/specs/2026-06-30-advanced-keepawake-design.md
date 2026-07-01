# Advanced Keep Awake Design Spec

## Overview
Enhance MeowOut's power assertion capabilities to support "Clamshell Mode" (preventing sleep when the laptop lid is closed) and battery safety mechanisms.

## Components

### 1. Sudoers-based Privilege Escalation (SudoersManager)
- **Purpose**: Allow MeowOut to run `sudo /usr/bin/pmset disablesleep 1` (and `0`) without prompting for a password every time.
- **Security**: The rule written to `/etc/sudoers.d/meowout-clamshell` will be strictly scoped to ONLY these two exact commands. It cannot be exploited for other root commands.
- **UX**: Exposed in Settings as "授予合盖运行权限". Clicking it triggers an AppleScript password prompt to install the rule.

### 2. Clamshell Mode Toggle
- **Initial State Snapshot**: Before enabling Clamshell mode for the first time, we run `pmset -g` to check the current `SleepDisabled` value. If it was already `1` (modified by the user or another app), we flag `wasAlreadyDisabled = true` and do not touch it.
- **Logic**: Integrates with `PowerAssertionService`. When "合盖不休眠" is toggled ON, and `wasAlreadyDisabled == false`, we run `sudo -n /usr/bin/pmset disablesleep 1`.
- **Normal Exit**: During `NSApplicationWillTerminate`, if we were the ones who set it to `1` (`wasAlreadyDisabled == false`), we run `sudo -n /usr/bin/pmset disablesleep 0` to clean up.
- **Crash Recovery**: We store a `UserDefaults` flag `didModifySleepDisabled = true` only when we actually switch it from `0` to `1`. On app launch, if this flag is `true` (meaning the app crashed or was force-quit before it could clean up), we silently revert `pmset` to `0` and reset the flag. This ensures we never overwrite a user's original `SleepDisabled 1` preference.

### 3. Battery Watchdog (BatteryProtectionService)
- **Logic**: A background `Task` or `Timer` that runs every 30 seconds while Keep Awake is active.
- **Condition**: Uses `IOKit` to check if the device is on battery (`isOnBattery`) and if the percentage is below the user's threshold.
- **UX**: A slider in Settings (e.g., 10% - 50%). If triggered, we automatically call `PowerAssertionService.shared.disable()`, revert Clamshell mode if active, and trigger a macOS local notification.

## Architecture & Integration
- Create `SudoersManager.swift` to handle rule installation, removal, and checking status.
- Update `PowerAssertionService.swift` to manage the `pmset` state alongside `IOPMAssertion`.
- Create `BatteryMonitor.swift` for `IOKit` battery queries.
- Update `SettingsView.swift` to add the new auth toggle and battery slider.
