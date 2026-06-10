import SwiftUI

struct ReportsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No reports yet",
                systemImage: "chart.bar.xaxis",
                description: Text("Performance reports will appear here once campaigns are connected.")
            )
            .navigationTitle("Reports")
        }
    }
}

#Preview {
    ReportsView()
}
