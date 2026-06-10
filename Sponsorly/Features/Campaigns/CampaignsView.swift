import SwiftUI

struct CampaignsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No campaigns yet",
                systemImage: "megaphone",
                description: Text("Sign in to your Amazon Ads account in Settings to load your campaigns.")
            )
            .navigationTitle("Campaigns")
        }
    }
}

#Preview {
    CampaignsView()
}
