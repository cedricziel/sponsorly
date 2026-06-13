import SwiftData
import SwiftUI

@main
struct SponsorlyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        // One shared SwiftData container for the durable report store; the
        // background refresh task reuses the same `ReportStore.sharedContainer`.
        .modelContainer(ReportStore.sharedContainer)
    }
}
