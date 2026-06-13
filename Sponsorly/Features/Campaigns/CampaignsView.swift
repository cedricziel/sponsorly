import SwiftUI

struct CampaignsView: View {
    @Environment(AccountsViewModel.self) private var accounts
    @State private var model = CampaignsViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Campaigns")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        AccountSwitcher()
                    }
                }
                .task(id: accounts.activeSelection) {
                    await model.load(using: accounts)
                }
                .refreshable {
                    await model.load(using: accounts)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if accounts.activeSelection == nil {
            ContentUnavailableView(
                "No Account Selected",
                systemImage: "person.crop.circle",
                description: Text("Choose an advertising account to see its campaigns.")
            )
        } else if model.isLoading, model.campaigns.isEmpty {
            ProgressView("Loading campaigns…")
        } else if let error = model.errorMessage, model.campaigns.isEmpty {
            ContentUnavailableView {
                Label("Couldn't Load Campaigns", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await model.load(using: accounts) } }
            }
        } else if model.campaigns.isEmpty {
            ContentUnavailableView(
                "No Campaigns",
                systemImage: "megaphone",
                description: Text("This account has no Sponsored Products campaigns.")
            )
        } else {
            List {
                if model.truncated {
                    Label("Showing the first results only.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.campaigns) { campaign in
                    NavigationLink {
                        CampaignDetailView(campaign: campaign)
                    } label: {
                        CampaignRow(campaign: campaign)
                    }
                }
            }
        }
    }
}

struct CampaignRow: View {
    let campaign: Campaign

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(campaign.name)
            HStack(spacing: 6) {
                CampaignStateBadge(state: campaign.state)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let budget = campaign.budget?.budget {
            parts.append(budget.formatted(.number.precision(.fractionLength(0 ... 2))))
        }
        if let type = campaign.targetingType {
            parts.append(type.capitalized)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct CampaignStateBadge: View {
    let state: String

    var body: some View {
        Text(state.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: .capsule)
            .foregroundStyle(color)
    }

    private var color: Color {
        switch state.uppercased() {
        case "ENABLED": .green
        case "PAUSED": .orange
        default: .secondary
        }
    }
}

#Preview("Campaigns") {
    let campaigns = [
        Campaign(
            campaignId: "1", name: "Brand — Auto", state: "ENABLED",
            targetingType: "AUTO", budget: .init(budget: 25, budgetType: "DAILY")
        ),
        Campaign(
            campaignId: "2", name: "Holiday Push", state: "PAUSED",
            targetingType: "MANUAL", budget: .init(budget: 100, budgetType: "DAILY")
        ),
    ]
    return NavigationStack {
        List(campaigns) { CampaignRow(campaign: $0) }
            .navigationTitle("Campaigns")
    }
}
