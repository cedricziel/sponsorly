import SwiftUI

/// A nav-bar control showing the active advertising profile (country flag +
/// name) that opens the account picker. Reads the shared `AccountsViewModel`
/// from the environment, so it stays in sync everywhere it appears.
struct AccountSwitcher: View {
    @Environment(AccountsViewModel.self) private var accounts
    @Environment(\.switchTab) private var switchTab
    @State private var isPickerPresented = false

    var body: some View {
        Button {
            // No accounts to pick yet — send the user to Settings to sign in.
            if accounts.hasConnectedRegions {
                isPickerPresented = true
            } else {
                switchTab(.settings)
            }
        } label: {
            if let profile = accounts.activeProfile {
                HStack(spacing: 4) {
                    Text(CountryFlag.emoji(profile.countryCode) ?? "🏷️")
                    Text(profile.accountName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            } else {
                Label("Account", systemImage: "person.crop.circle")
            }
        }
        .sheet(isPresented: $isPickerPresented) {
            NavigationStack {
                AccountsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isPickerPresented = false }
                        }
                    }
            }
        }
    }
}

#Preview {
    NavigationStack {
        Text("Screen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { AccountSwitcher() }
            }
    }
    .environment(AccountsViewModel.previewModel())
}
