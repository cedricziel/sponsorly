import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            CampaignsView()
                .tabItem { Label("Campaigns", systemImage: "megaphone") }
            ReportsView()
                .tabItem { Label("Reports", systemImage: "chart.bar.xaxis") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

#Preview {
    RootView()
}
