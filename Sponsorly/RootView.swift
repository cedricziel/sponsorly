import SwiftUI

/// The app's top-level tabs. Used to drive `TabView` selection so features can
/// route the user to another tab (e.g. send them to Settings to sign in).
enum AppTab: Hashable {
    case overview, campaigns, settings
}

extension EnvironmentValues {
    /// Switches the selected top-level tab. Defaults to a no-op so views work in
    /// isolation (previews); `RootView` injects the real implementation.
    @Entry var switchTab: (AppTab) -> Void = { _ in }
}

struct RootView: View {
    @State private var auth: AuthViewModel
    @State private var accounts: AccountsViewModel
    @State private var selectedTab: AppTab = .overview

    init() {
        let auth = AuthViewModel()
        _auth = State(initialValue: auth)
        _accounts = State(initialValue: AccountsViewModel(auth: auth))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ReportsView()
                .tag(AppTab.overview)
                .tabItem { Label("Overview", systemImage: "chart.bar.xaxis") }
            CampaignsView()
                .tag(AppTab.campaigns)
                .tabItem { Label("Campaigns", systemImage: "megaphone") }
            SettingsView()
                .tag(AppTab.settings)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .environment(auth)
        .environment(accounts)
        .environment(\.switchTab) { selectedTab = $0 }
        .task {
            await auth.restore()
            await accounts.load()
        }
    }
}

#Preview {
    RootView()
}
