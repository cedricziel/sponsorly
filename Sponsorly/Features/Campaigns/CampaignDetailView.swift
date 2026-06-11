import SwiftUI

struct CampaignDetailView: View {
    let campaign: Campaign

    @Environment(AccountsViewModel.self) private var accounts
    @State private var model = AdGroupsViewModel()
    @State private var isHarvesting = false

    private var isAuto: Bool {
        campaign.targetingType?.uppercased() == "AUTO"
    }

    var body: some View {
        content
            .navigationTitle(campaign.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isAuto {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { isHarvesting = true } label: {
                            Label("Harvest", systemImage: "leaf")
                        }
                    }
                }
            }
            .sheet(isPresented: $isHarvesting) {
                HarvestWizardView(campaign: campaign, accounts: accounts)
            }
            .task { await model.load(campaignId: campaign.campaignId, using: accounts) }
            .refreshable { await model.load(campaignId: campaign.campaignId, using: accounts) }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading, model.adGroups.isEmpty {
            ProgressView("Loading ad groups…")
        } else if let error = model.errorMessage, model.adGroups.isEmpty {
            ContentUnavailableView {
                Label("Couldn't Load Ad Groups", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") {
                    Task { await model.load(campaignId: campaign.campaignId, using: accounts) }
                }
            }
        } else if model.adGroups.isEmpty {
            ContentUnavailableView(
                "No Ad Groups",
                systemImage: "rectangle.stack",
                description: Text("This campaign has no ad groups.")
            )
        } else {
            List {
                Section {
                    CampaignStateBadge(state: campaign.state)
                }
                Section("Ad Groups") {
                    if model.truncated {
                        Label("Showing the first results only.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.adGroups) { adGroup in
                        NavigationLink {
                            AdGroupDetailView(adGroup: adGroup)
                        } label: {
                            AdGroupRow(adGroup: adGroup)
                        }
                    }
                }
            }
        }
    }
}

struct AdGroupRow: View {
    let adGroup: AdGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(adGroup.name)
            HStack(spacing: 6) {
                CampaignStateBadge(state: adGroup.state)
                if let bid = adGroup.defaultBid {
                    Text("Bid \(bid.formatted(.number.precision(.fractionLength(0 ... 2))))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview("Ad groups") {
    NavigationStack {
        List {
            AdGroupRow(adGroup: AdGroup(
                adGroupId: "1", name: "Exact — Core", state: "ENABLED", defaultBid: 0.75
            ))
            AdGroupRow(adGroup: AdGroup(
                adGroupId: "2", name: "Broad — Discovery", state: "PAUSED", defaultBid: 0.45
            ))
        }
        .navigationTitle("Campaign")
    }
}
