import Charts
import SwiftUI

struct ReportsView: View {
    @Environment(AccountsViewModel.self) private var accounts
    @Environment(\.switchTab) private var switchTab
    @State private var model = SpendOverviewViewModel()
    @State private var selectedDate: Date?

    /// The active profile's currency, used to format all monetary figures.
    private var currency: String? {
        accounts.activeProfile?.currencyCode
    }

    /// The trend point nearest the scrubbed x-position, if any.
    private var selectedPoint: DailySpend? {
        guard let selectedDate else { return nil }
        return model.trend.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Overview")
                .navigationBarTitleDisplayMode(.inline)
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
            ContentUnavailableView {
                Label("No Account Selected", systemImage: "person.crop.circle")
            } description: {
                Text("Choose an advertising account to see your spend.")
            } actions: {
                Button("Go to Settings") { switchTab(.settings) }
                    .buttonStyle(.borderedProminent)
            }
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
            MetricTile(title: "Spend (30d)", value: Money.string(model.headline.spend, currencyCode: currency))
            MetricTile(title: "Sales (30d)", value: Money.string(model.headline.sales, currencyCode: currency))
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
                Text(model.todaySpend.map { Money.string($0, currencyCode: currency) } ?? "—")
                    .font(.title2.weight(.semibold))
                    .contentTransition(.numericText())
            }
        }
    }

    private var trendCard: some View {
        OverviewCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Spend trend (30d)").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    if let selectedPoint {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Money.string(selectedPoint.spend, currencyCode: currency))
                                .font(.callout.weight(.semibold))
                                .contentTransition(.numericText())
                            Text(selectedPoint.date, format: .dateTime.month().day())
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Chart(model.trend) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Spend", point.spend)
                    )
                    .interpolationMethod(.monotone)

                    if let selectedPoint, selectedPoint.id == point.id {
                        RuleMark(x: .value("Date", selectedPoint.date))
                            .foregroundStyle(.secondary.opacity(0.3))
                        PointMark(
                            x: .value("Date", selectedPoint.date),
                            y: .value("Spend", selectedPoint.spend)
                        )
                        .symbolSize(70)
                    }
                }
                .frame(height: 140)
                .chartXSelection(value: $selectedDate)
                .sensoryFeedback(.selection, trigger: selectedPoint?.id)
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
                            Text(Money.string(campaign.spend, currencyCode: currency)).font(.callout.weight(.medium))
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

/// Number formatting for the overview. When a profile's `currencyCode` is
/// known, amounts render in that currency; otherwise they fall back to a plain
/// two-decimal number.
enum Money {
    static func string(_ value: Double, currencyCode: String? = nil) -> String {
        if let currencyCode {
            return value.formatted(.currency(code: currencyCode).precision(.fractionLength(2)))
        }
        return value.formatted(.number.precision(.fractionLength(2)))
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
