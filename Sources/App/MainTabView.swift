import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appModel: UniOSAppModel

    var body: some View {
        TabView(selection: $appModel.selectedTab) {
            NavigationStack {
                ChatListView()
            }
            .tabItem {
                Label(AppTab.chats.title, systemImage: AppTab.chats.systemImage)
            }
            .tag(AppTab.chats)

            NavigationStack {
                ContactsView()
            }
            .tabItem {
                Label(AppTab.contacts.title, systemImage: AppTab.contacts.systemImage)
            }
            .tag(AppTab.contacts)

            NavigationStack {
                CallsView()
            }
            .tabItem {
                Label(AppTab.calls.title, systemImage: AppTab.calls.systemImage)
            }
            .tag(AppTab.calls)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage)
            }
            .tag(AppTab.settings)
        }
        .onChange(of: appModel.selectedTab) { tab in
            appModel.select(tab: tab)
        }
    }
}
