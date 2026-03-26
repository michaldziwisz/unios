import SwiftUI

@main
struct UniOSApp: App {
    @StateObject private var appModel = UniOSAppModel()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(appModel)
                .tint(UniOSTheme.tint)
        }
    }
}

