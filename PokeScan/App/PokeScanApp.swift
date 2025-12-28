import SwiftUI

@main
struct PokeScanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: OverlayWindow?
    private var keyMonitor: Any?

    private let dex = PokemonDex()
    private lazy var socketClient = SocketClient(dex: dex)
    private let criteria = CriteriaEngine()
    private let alerts = AlertManager()
    private let windowController = OverlayWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = ContentView()
            .environmentObject(socketClient)
            .environmentObject(criteria)
            .environmentObject(alerts)
            .environmentObject(dex)
            .environmentObject(windowController)

        window = OverlayWindow(rootView: contentView, controller: windowController)
        window?.makeKeyAndOrderFront(nil)
        socketClient.start()
        installKeyMonitor()
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == 49 { // Space
                self.alerts.clearFlash()
                return nil
            }
            if let chars = event.charactersIgnoringModifiers, let digit = Int(chars), digit >= 1, digit <= 9 {
                let keys = self.criteria.profileKeys()
                let index = digit - 1
                if index < keys.count {
                    self.criteria.setActiveProfile(keys[index])
                    return nil
                }
            }
            return event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
