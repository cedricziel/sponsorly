import Charts
import SwiftUI

struct ReportsView: View {
    @Environment(AccountsViewModel.self) private var accounts
    @State private var model = SpendOverviewViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Overview")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        AccountSwitcher()
                    }
                }
                .task(id: accounts.activeSelection) { await model.load(using: accounts) }
                .refreshable { await model.load(using: accounts) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if accounts.activeSelection == nil {
            ContentUnavailableView(
                "No Account Selected",
                systemImage: "person.crop.circle",
                description: Text("Choose an advertising account to see your spend.")
            )
        } else if model.isLoading, model.isEmpty {
            ProgressView("Loading overview…")
        } else if let error = model.errorMessage, model.isEmpty {
            ContentUnavailableView {
                Label("Couldn't Load Overview", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await model.load(using: accounts) } }
            }
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    headlineTiles
                    todayTile
                    if !model.trend.isEmpty { trendCard }
                    if !model.topCampaigns.isEmpty { topCampaignsCard }
                }
                .padding()
            }
        }
    }

    private var headlineTiles: some View {
        HStack(spacing: 12) {
            MetricTile(title: "Spend (30d)", value: Money.string(model.headline.spend))
            MetricTile(title: "Sales (30d)", value: Money.string(model.headline.sales))
            MetricTile(title: "ACOS", value: Money.percent(model.headline.acos))
        }
    }

    private var todayTile: some View {
        OverviewCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today so far").font(.subheadline).foregroundStyle(.secondary)
                    Text("approx.").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Text(model.todaySpend.map(Money.string) ?? "—")
                    .font(.title2.weight(.semibold))
                    .contentTransition(.numericText())
            }
        }
    }

    private var trendCard: some View {
        OverviewCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Spend trend (30d)").font(.subheadline).foregroundStyle(.secondary)
                Chart(model.trend) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Spend", point.spend)
                    )
                    .interpolationMethod(.monotone)
                }
                .frame(height: 140)
            }
        }
    }

    private var topCampaignsCard: some View {
        OverviewCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Top campaigns by spend").font(.subheadline).foregroundStyle(.secondary)
                ForEach(model.topCampaigns) { campaign in
                    HStack {
                        Text(campaign.name).lineLimit(1)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Money.string(campaign.spend)).font(.callout.weight(.medium))
                            Text("ACOS \(Money.percent(campaign.acos))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

/// A compact metric tile.
struct MetricTile: View {
    let title: String
    let value: String

    var body: some View {
        OverviewCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(value).font(.title3.weight(.semibold)).minimumScaleFactor(0.7).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A rounded card container used across the overview.
struct OverviewCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .background(.background.secondary, in: .rect(cornerRadius: 12))
    }
}

/// Number formatting for the overview (currency symbol is a follow-up).
enum Money {
    static func string(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    static func percent(_ ratio: Double?) -> String {
        guard let ratio else { return "—" }
        return ratio.formatted(.percent.precision(.fractionLength(1)))
    }
}

#Preview {
    ReportsView()
        .environment(AccountsViewModel.previewModel())
}
