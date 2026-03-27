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
        .safeAreaInset(edge: .bottom) {
            if appModel.isAuthenticated, appModel.activeCallSession != nil {
                ActiveCallPanelView()
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .background(Color.clear)
            }
        }
    }
}
