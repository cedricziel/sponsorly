import AmazonAdsCore
import SwiftUI

struct AccountsView: View {
    @Environment(AccountsViewModel.self) private var model

    var body: some View {
        List {
            if !model.hasConnectedRegions {
                ContentUnavailableView(
                    "No Regions Connected",
                    systemImage: "globe",
                    description: Text("Connect a region in Settings to see your advertising accounts.")
                )
            } else {
                ForEach(model.connectedRegions, id: \.self) { region in
                    Section(region.displayName) {
                        regionContent(region)
                    }
                }
            }
        }
        .navigationTitle("Accounts")
        .overlay {
            if model.isLoading, model.accounts.isEmpty {
                ProgressView()
            }
        }
        .refreshable { await model.load() }
        .task { await model.load() }
    }

    @ViewBuilder
    private func regionContent(_ region: AmazonRegion) -> some View {
        if let failure = model.failure(in: region) {
            Label(failure, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.callout)
        }
        let profiles = model.profiles(in: region)
        if profiles.isEmpty, model.failure(in: region) == nil {
            Text("No advertising accounts")
                .foregroundStyle(.secondary)
        }
        ForEach(profiles) { profile in
            Button {
                model.select(profile)
            } label: {
                profileRow(profile)
            }
            .buttonStyle(.plain)
        }
    }

    private func profileRow(_ profile: AdvertisingProfile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.accountName)
                    .foregroundStyle(.primary)
                if let subtitle = subtitle(for: profile) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.isActive(profile) {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .fontWeight(.semibold)
            }
        }
        .contentShape(.rect)
    }

    private func subtitle(for profile: AdvertisingProfile) -> String? {
        var parts: [String] = []
        if let manager = profile.managerAccountName { parts.append(manager) }
        if let country = profile.countryCode { parts.append(country) }
        if let type = profile.accountType { parts.append(type) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

#Preview("No regions") {
    NavigationStack {
        AccountsView()
    }
    .environment(AccountsViewModel.previewModel())
}

#Preview("Connected") {
    let profiles = [
        AdvertisingProfile(
            profileId: "1", region: .europe, accountName: "My DE Store",
            countryCode: "DE", accountType: "seller", managerAccountName: nil
        ),
        AdvertisingProfile(
            profileId: "2", region: .europe, accountName: "Agency Brand",
            countryCode: "FR", accountType: nil, managerAccountName: "Acme Agency"
        ),
        AdvertisingProfile(
            profileId: "9", region: .northAmerica, accountName: "US Vendor",
            countryCode: "US", accountType: "vendor", managerAccountName: nil
        )
    ]
    return NavigationStack { AccountsView() }
        .environment(AccountsViewModel.loaded(
            ConnectedAccounts(profiles: profiles),
            active: ActiveProfileSelection(region: .europe, profileId: "1")
        ))
}

#Preview("Partial failure") {
    let profiles = [
        AdvertisingProfile(
            profileId: "1", region: .europe, accountName: "My DE Store",
            countryCode: "DE", accountType: "seller", managerAccountName: nil
        )
    ]
    var accounts = ConnectedAccounts(profiles: profiles)
    accounts.failures[.northAmerica] = "Amazon returned HTTP 500."
    return NavigationStack { AccountsView() }
        .environment(AccountsViewModel.loaded(accounts))
}
