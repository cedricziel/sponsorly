import AmazonAdsCore
import SwiftUI

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var auth

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(AmazonRegion.allCases) { region in
                        regionRow(region)
                    }
                } header: {
                    Text("Amazon Regions")
                } footer: {
                    Text("Connect each region where you advertise. "
                        + "Accounts from all connected regions appear together.")
                }

                Section("Advertising") {
                    NavigationLink {
                        AccountsView()
                    } label: {
                        Text("Accounts")
                    }
                    .disabled(auth.connectedRegions.isEmpty)
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.appVersion)
                }
            }
            .navigationTitle("Settings")
            .alert(
                "Sign-in failed",
                isPresented: Binding(
                    get: { auth.errorMessage != nil },
                    set: { if !$0 { auth.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(auth.errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func regionRow(_ region: AmazonRegion) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(region.displayName)
                if auth.isConnected(region) {
                    Label("Connected", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.green)
                }
            }
            Spacer()
            if auth.isBusy(region) {
                ProgressView()
            } else if auth.isConnected(region) {
                Button("Sign Out", role: .destructive) {
                    Task { await auth.signOut(region: region) }
                }
            } else {
                Button("Sign In") {
                    Task { await auth.signIn(region: region) }
                }
            }
        }
    }
}

private extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }
}

#Preview("No regions") {
    let auth = AuthViewModel.previewModel(connected: [])
    return SettingsView()
        .environment(auth)
        .environment(AccountsViewModel.previewModel(auth: auth))
}

#Preview("EU connected") {
    let auth = AuthViewModel.previewModel(connected: [.europe])
    return SettingsView()
        .environment(auth)
        .environment(AccountsViewModel.previewModel(auth: auth))
}
