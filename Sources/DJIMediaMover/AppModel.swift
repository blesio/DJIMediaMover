import AppKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var update = TransferUpdate(stage: .idle)
    @Published var volumes: [URL] = []
    @Published var destination: URL?
    @Published var isWorking = false
    @Published var isUnmounting = false
    @Published var automaticImport = true
    @Published var autoUnmount = false
    let monitor = VolumeMonitor()
    private let engine = TransferEngine()
    private var handledConnection = Set<String>()
    private var retryTask: Task<Void, Never>?
    private var retryAttempt = 0
    private var isAccessingDestination = false
    private var settingsWindow: NSWindow?
    private var mainWindow: NSWindow?
    private var didStart = false

    init() {
        restoreDestinationAccess()
        automaticImport = UserDefaults.standard.object(forKey: "automaticImport") as? Bool ?? true
        autoUnmount = UserDefaults.standard.object(forKey: "autoUnmount") as? Bool ?? false
        monitor.onChange = { [weak self] volumes in self?.volumesChanged(volumes) }
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        NSApp.setActivationPolicy(.accessory)
        monitor.start()
    }

    func chooseDestination() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            if isAccessingDestination { destination?.stopAccessingSecurityScopedResource() }
            destination = url
            isAccessingDestination = url.startAccessingSecurityScopedResource()
            UserDefaults.standard.set(url.path, forKey: "destination")
            if let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(bookmark, forKey: "destinationBookmark")
            }
            if automaticImport, !volumes.isEmpty { begin() }
        }
    }

    func setAutomatic(_ value: Bool) { automaticImport = value; UserDefaults.standard.set(value, forKey: "automaticImport") }

    func setAutoUnmount(_ value: Bool) { autoUnmount = value; UserDefaults.standard.set(value, forKey: "autoUnmount") }

    func windowClosed() {
        NSApp.setActivationPolicy(.accessory)
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "DJI Media Mover Settings"
            window.contentView = NSHostingView(rootView: SettingsView(model: self))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showMainWindow() {
        guard !volumes.isEmpty else { return }
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "DJI Media Mover"
            window.contentView = NSHostingView(rootView: ContentView(model: self))
            window.isReleasedWhenClosed = false
            window.center()
            mainWindow = window
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func unmountDroneStorage() {
        guard !isWorking, !isUnmounting, !volumes.isEmpty else { return }
        let paths = volumes.map(\.path)
        isUnmounting = true
        update.message = "Unmounting DJI storage…"
        Task {
            let errors = await Task.detached { () -> [String] in
                var failures: [String] = []
                for path in paths {
                    let process = Process()
                    let output = Pipe()
                    process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                    process.arguments = ["unmount", path]
                    process.standardOutput = output
                    process.standardError = output
                    do {
                        try process.run()
                        process.waitUntilExit()
                        if process.terminationStatus != 0 {
                            let data = output.fileHandleForReading.readDataToEndOfFile()
                            let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                            failures.append(detail ?? "Could not unmount \(path)")
                        }
                    } catch {
                        failures.append("\(path): \(error.localizedDescription)")
                    }
                }
                return failures
            }.value
            isUnmounting = false
            if errors.isEmpty {
                update.message = "DJI storage unmounted safely."
                showUnmountSuccessAlert()
            } else {
                update.message = errors.joined(separator: "\n")
            }
        }
    }

    private func showUnmountSuccessAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "DJI Storage Unmounted"
        alert.informativeText = "The DJI storage was unmounted successfully. It is now safe to disconnect the drone."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func begin() {
        retryTask?.cancel()
        retryTask = nil
        startTransfer()
    }

    private func startTransfer() {
        guard !isWorking, let destination, !volumes.isEmpty else { return }
        isWorking = true
        NSApp.activate(ignoringOtherApps: true)
        Task {
            await engine.transfer(volumes: volumes, destination: destination) { [weak self] value in
                await MainActor.run { self?.update = value }
            }
            isWorking = false
            if !update.copyErrors.isEmpty, automaticImport, !volumes.isEmpty {
                scheduleRetry()
            } else if update.stage == .complete {
                retryAttempt = 0
                if autoUnmount, update.found > 0, !volumes.isEmpty {
                    unmountDroneStorage()
                }
            }
        }
    }

    private func scheduleRetry() {
        let delays = [10, 30, 60, 120, 300]
        let delay = delays[min(retryAttempt, delays.count - 1)]
        retryAttempt += 1
        update.message += " Automatic retry in \(delay) seconds."
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.startTransfer() }
        }
    }

    private func volumesChanged(_ newVolumes: [URL]) {
        volumes = newVolumes
        let identities = Set(newVolumes.map(\.path))
        handledConnection.formIntersection(identities)
        guard !newVolumes.isEmpty else {
            retryTask?.cancel(); retryTask = nil; retryAttempt = 0
            update = TransferUpdate(stage: .idle)
            mainWindow?.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)
            return
        }
        showMainWindow()
        if automaticImport, destination != nil, !identities.isSubset(of: handledConnection) {
            handledConnection.formUnion(identities)
            begin()
        } else if destination == nil {
            update.message = "DJI connected. Choose an import destination."
        }
    }

    private func restoreDestinationAccess() {
        if let bookmark = UserDefaults.standard.data(forKey: "destinationBookmark") {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
                destination = url
                isAccessingDestination = url.startAccessingSecurityScopedResource()
                if stale, let refreshed = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(refreshed, forKey: "destinationBookmark")
                }
                return
            }
        }
        if let saved = UserDefaults.standard.string(forKey: "destination") {
            let url = URL(fileURLWithPath: saved)
            destination = url
            isAccessingDestination = url.startAccessingSecurityScopedResource()
            if let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(bookmark, forKey: "destinationBookmark")
            }
        }
    }
}
