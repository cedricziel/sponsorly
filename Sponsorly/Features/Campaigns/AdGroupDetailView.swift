import SwiftUI

struct AdGroupDetailView: View {
    let adGroup: AdGroup

    @Environment(AccountsViewModel.self) private var accounts
    @State private var model = AdGroupDetailViewModel()

    var body: some View {
        content
            .navigationTitle(adGroup.name)
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.load(adGroupId: adGroup.adGroupId, using: accounts) }
            .refreshable { await model.load(adGroupId: adGroup.adGroupId, using: accounts) }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading, model.isEmpty {
            ProgressView("Loading ad group…")
        } else if let error = model.errorMessage {
            ContentUnavailableView {
                Label("Couldn't Load Ad Group", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") {
                    Task { await model.load(adGroupId: adGroup.adGroupId, using: accounts) }
                }
            }
        } else if model.isEmpty {
            ContentUnavailableView(
                "Nothing Here",
                systemImage: "tray",
                description: Text("This ad group has no products or targeting.")
            )
        } else {
            List {
                Section { CampaignStateBadge(state: adGroup.state) }

                if !model.productAds.isEmpty {
                    Section("Products (\(model.productAds.count))") {
                        ForEach(model.productAds) { ProductAdRow(productAd: $0) }
                    }
                }
                if !model.keywords.isEmpty {
                    Section("Keywords (\(model.keywords.count))") {
                        ForEach(model.keywords) { KeywordRow(keyword: $0) }
                    }
                }
                if !model.targetingClauses.isEmpty {
                    Section("Targeting (\(model.targetingClauses.count))") {
                        ForEach(model.targetingClauses) { TargetRow(target: $0) }
                    }
                }
            }
        }
    }
}

struct ProductAdRow: View {
    let productAd: ProductAd

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(productAd.asin ?? productAd.sku ?? productAd.adId)
                    .monospaced()
                if let sku = productAd.sku, productAd.asin != nil {
                    Text(sku).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            CampaignStateBadge(state: productAd.state)
        }
    }
}

struct KeywordRow: View {
    let keyword: Keyword

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(keyword.keywordText)
            HStack(spacing: 6) {
                CampaignStateBadge(state: keyword.state)
                if let matchType = keyword.matchType {
                    Text(matchType.capitalized).font(.caption).foregroundStyle(.secondary)
                }
                if let bid = keyword.bid {
                    Text("Bid \(bid.formatted(.number.precision(.fractionLength(0 ... 2))))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct TargetRow: View {
    let target: TargetingClause

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(target.displayExpression)
            HStack(spacing: 6) {
                CampaignStateBadge(state: target.state)
                if let bid = target.bid {
                    Text("Bid \(bid.formatted(.number.precision(.fractionLength(0 ... 2))))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview("Ad group contents") {
    NavigationStack {
        List {
            Section("Products (1)") {
                ProductAdRow(productAd: ProductAd(adId: "1", asin: "B0ABCD1234", sku: "SKU-9", state: "ENABLED"))
            }
            Section("Keywords (1)") {
                KeywordRow(keyword: Keyword(
                    keywordId: "1", keywordText: "running shoes", matchType: "EXACT",
                    state: "ENABLED", bid: 0.85
                ))
            }
            Section("Targeting (1)") {
                TargetRow(target: TargetingClause(
                    targetId: "1", state: "PAUSED", bid: 0.40,
                    expression: [.init(type: "ASIN_CATEGORY_SAME_AS", value: "Shoes")]
                ))
            }
        }
        .navigationTitle("Ad Group")
    }
}
