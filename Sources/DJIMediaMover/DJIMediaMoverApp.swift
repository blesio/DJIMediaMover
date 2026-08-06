import SwiftUI
import AppKit

@main
struct DJIMediaMoverApp: App {
    @StateObject private var model = AppModel()
    private let menuBarIcon: NSImage = {
        if let url = Bundle.main.url(forResource: "MenuBarDJI", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            image.size = NSSize(width: 24, height: 14)
            image.accessibilityDescription = "DJI Media Mover"
            return image
        }
        return NSImage(systemSymbolName: "externaldrive.fill.badge.checkmark", accessibilityDescription: "DJI Media Mover")!
    }()

    init() {
        // This is a menu-bar utility; its windows can appear without a Dock icon.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            Button("Show DJI Media Mover") {
                model.showMainWindow()
            }.disabled(model.volumes.isEmpty)
            Divider()
            Text(model.update.stage.rawValue)
            Button("Import Immediately") { model.begin() }
                .disabled(model.isWorking || model.destination == nil || model.volumes.isEmpty)
            Button("Unmount DJI Storage") { model.unmountDroneStorage() }
                .disabled(model.isWorking || model.isUnmounting || model.volumes.isEmpty)
            Divider()
            Button("Settings…") { model.showSettings() }
            Button("Quit") { NSApp.terminate(nil) }
        } label: {
            Image(nsImage: menuBarIcon).onAppear { model.start() }
        }
    }
}
