import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var appModel: UniOSAppModel

    var body: some View {
        Group {
            if appModel.isAuthenticated {
                MainTabView()
            } else {
                SignInView()
            }
        }
        .background(UniOSTheme.canvas.ignoresSafeArea())
    }
}

