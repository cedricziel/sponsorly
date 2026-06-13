import SwiftData
import SwiftUI

@main
struct SponsorlyApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Must register the handler before launch finishes.
        BackgroundRefreshScheduler.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        // One shared SwiftData container for the durable report store; the
        // background refresh task reuses the same `ReportStore.sharedContainer`.
        .modelContainer(ReportStore.sharedContainer)
        // Queue the next overnight warm whenever the app backgrounds.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { BackgroundRefreshScheduler.schedule() }
        }
    }
}
