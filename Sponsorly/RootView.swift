import SwiftUI

struct RootView: View {
    @State private var auth: AuthViewModel
    @State private var accounts: AccountsViewModel

    init() {
        let auth = AuthViewModel()
        _auth = State(initialValue: auth)
        _accounts = State(initialValue: AccountsViewModel(auth: auth))
    }

    var body: some View {
        TabView {
            CampaignsView()
                .tabItem { Label("Campaigns", systemImage: "megaphone") }
            ReportsView()
                .tabItem { Label("Reports", systemImage: "chart.bar.xaxis") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .environment(auth)
        .environment(accounts)
        .task {
            await auth.restore()
            await accounts.load()
        }
    }
}

#Preview {
    RootView()
}
