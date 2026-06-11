import SwiftUI

struct HarvestWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: HarvestViewModel

    init(campaign: Campaign, accounts: AccountsViewModel) {
        _model = State(initialValue: HarvestViewModel(campaign: campaign, accounts: accounts))
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading, model.allTerms.isEmpty {
                    ProgressView("Loading search terms…")
                } else if let error = model.errorMessage, model.allTerms.isEmpty {
                    APIErrorView(message: error, responseBody: model.errorResponseBody) {
                        Task { await model.loadReport() }
                    }
                } else {
                    switch model.step {
                    case .criteria: HarvestCriteriaStep(model: model)
                    case .review: HarvestReviewStep(model: model)
                    case .results: HarvestResultsStep(model: model)
                    }
                }
            }
            .navigationTitle("Harvest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.step == .results ? "Done" : "Cancel") { dismiss() }
                }
            }
            .task {
                await model.loadTargets()
                await model.loadReport()
            }
        }
    }
}

private struct HarvestCriteriaStep: View {
    @Bindable var model: HarvestViewModel

    var body: some View {
        Form {
            Section("Graduate when") {
                Stepper("Min orders: \(model.criteria.minOrders)", value: $model.criteria.minOrders, in: 1 ... 50)
                Stepper("Min clicks: \(model.criteria.minClicks)", value: $model.criteria.minClicks, in: 1 ... 200)
                HStack {
                    Text("Target ACOS")
                    Spacer()
                    Text(model.criteria.targetACOS.formatted(.percent.precision(.fractionLength(0))))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $model.criteria.targetACOS, in: 0.05 ... 1.0, step: 0.05)
            }
            Section("Negate when") {
                Stepper(
                    "Min clicks, 0 orders: \(model.criteria.negateMinClicks)",
                    value: $model.criteria.negateMinClicks, in: 1 ... 200
                )
            }
            Section("Promote into") {
                Picker("Manual campaign", selection: $model.targetCampaignId) {
                    Text("Choose…").tag(String?.none)
                    ForEach(model.manualCampaigns) { Text($0.name).tag(String?.some($0.campaignId)) }
                }
                .onChange(of: model.targetCampaignId) { _, new in
                    if let new { Task { await model.loadAdGroups(for: new) } }
                }
                if !model.targetAdGroups.isEmpty {
                    Picker("Ad group", selection: $model.targetAdGroupId) {
                        Text("Choose…").tag(String?.none)
                        ForEach(model.targetAdGroups) { Text($0.name).tag(String?.some($0.adGroupId)) }
                    }
                }
                HStack {
                    Text("Starting bid")
                    Spacer()
                    Text(model.bid.formatted(.number.precision(.fractionLength(2))))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $model.bid, in: 0.05 ... 5.0, step: 0.05)
            }
            Section {
                Button("Review \(model.graduateTerms.count + model.negateTerms.count) terms") {
                    model.step = .review
                }
                .disabled(model.graduateTerms.isEmpty && model.negateTerms.isEmpty)
            }
        }
    }
}

private struct HarvestReviewStep: View {
    @Bindable var model: HarvestViewModel

    var body: some View {
        List {
            bucket(
                "Graduate (\(model.graduateTerms.count))", terms: model.graduateTerms,
                selection: $model.selectedGraduate
            )
            bucket(
                "Negate (\(model.negateTerms.count))", terms: model.negateTerms,
                selection: $model.selectedNegate
            )
        }
        .safeAreaInset(edge: .bottom) { confirmBar }
    }

    private func bucket(_ title: String, terms: [SearchTerm], selection: Binding<Set<String>>) -> some View {
        Section(title) {
            if terms.isEmpty {
                Text("None").foregroundStyle(.secondary)
            }
            ForEach(terms) { term in
                let isSelected = selection.wrappedValue.contains(term.id)
                Button {
                    if isSelected {
                        selection.wrappedValue.remove(term.id)
                    } else {
                        selection.wrappedValue.insert(term.id)
                    }
                } label: {
                    HStack {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(term.term).lineLimit(1)
                            Text("\(term.clicks) clk · \(term.orders) ord · ACOS \(Money.percent(term.acos))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var confirmBar: some View {
        VStack(spacing: 8) {
            Text("Create \(model.selectedGraduateCount) keywords · negate \(model.totalNegateCount) terms")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Back") { model.step = .criteria }
                Spacer()
                Button {
                    Task { await model.apply() }
                } label: {
                    if model.isWriting { ProgressView() } else { Text("Confirm & Apply") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canConfirm || model.isWriting || model.targetNotReady)
            }
        }
        .padding()
        .background(.bar)
    }
}

private struct HarvestResultsStep: View {
    let model: HarvestViewModel

    var body: some View {
        List {
            Section {
                Label("\(count(.keyword, .succeeded)) keywords added", systemImage: "checkmark.circle")
                Label("\(count(.negative, .succeeded)) negated", systemImage: "checkmark.circle")
                if existing > 0 { Label("\(existing) already existed", systemImage: "info.circle") }
                if failed > 0 {
                    Label("\(failed) failed", systemImage: "xmark.circle").foregroundStyle(.red)
                }
            }
            Section("Details") {
                ForEach(model.results) { outcome in
                    HStack {
                        Text(outcome.term).lineLimit(1)
                        Spacer()
                        Text(label(outcome)).font(.caption).foregroundStyle(color(outcome))
                    }
                }
            }
        }
    }

    private func count(_ kind: WriteOutcome.Kind, _ status: WriteStatus) -> Int {
        model.results.filter { $0.kind == kind && $0.status == status }.count
    }

    private var existing: Int {
        model.results.filter { $0.status == .alreadyExists }.count
    }

    private var failed: Int {
        model.results.filter { if case .failed = $0.status { return true }; return false }.count
    }

    private func label(_ outcome: WriteOutcome) -> String {
        let prefix = outcome.kind == .keyword ? "kw" : "neg"
        switch outcome.status {
        case .succeeded: return "\(prefix) ✓"
        case .alreadyExists: return "\(prefix) exists"
        case let .failed(reason): return "\(prefix) ✗ \(reason)"
        }
    }

    private func color(_ outcome: WriteOutcome) -> Color {
        switch outcome.status {
        case .succeeded: .green
        case .alreadyExists: .secondary
        case .failed: .red
        }
    }
}

extension HarvestViewModel {
    /// The target must be chosen before any graduation can be applied.
    var targetNotReady: Bool {
        !selectedGraduate.isEmpty && (targetCampaignId == nil || targetAdGroupId == nil)
    }
}

#Preview("Criteria") {
    NavigationStack { HarvestCriteriaStep(model: .preview(step: .criteria)) }
}

#Preview("Review") {
    NavigationStack { HarvestReviewStep(model: .preview(step: .review)) }
}

#Preview("Results") {
    NavigationStack { HarvestResultsStep(model: .preview(step: .results)) }
}
