import SwiftUI

@main
struct TMUnstuckApp: App {
    @StateObject private var monitor = TMMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(monitor)
        } label: {
            Image(systemName: monitor.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}
