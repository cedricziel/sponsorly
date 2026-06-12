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
                pill {
                    Text(CountryFlag.emoji(profile.countryCode) ?? "🏷️")
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(profile.accountName)
            } else {
                pill {
                    Image(systemName: "person.crop.circle")
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Account")
            }
        }
        .buttonStyle(.plain)
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

    /// A compact capsule wrapper used for both the selected and empty states.
    private func pill(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 4) { content() }
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: .capsule)
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
