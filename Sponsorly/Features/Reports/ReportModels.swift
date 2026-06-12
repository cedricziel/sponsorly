import Foundation

/// Request body for `POST /reporting/reports` (Reporting API v3).
struct ReportRequest: Encodable {
    let name: String
    let startDate: String // yyyy-MM-dd
    let endDate: String
    let configuration: Configuration

    struct Configuration: Encodable {
        let adProduct: String
        let groupBy: [String]
        let columns: [String]
        let reportTypeId: String
        let timeUnit: String
        let format: String
        var filters: [Filter]?
    }

    /// A report column filter, e.g. scope to one campaign.
    struct Filter: Encodable {
        let field: String
        let values: [String]
    }

    /// A campaign-level Sponsored Products report.
    static func spCampaigns(
        name: String,
        startDate: String,
        endDate: String,
        timeUnit: String,
        columns: [String]
    ) -> ReportRequest {
        ReportRequest(
            name: name,
            startDate: startDate,
            endDate: endDate,
            configuration: Configuration(
                adProduct: "SPONSORED_PRODUCTS",
                groupBy: ["campaign"],
                columns: columns,
                reportTypeId: "spCampaigns",
                timeUnit: timeUnit,
                format: "GZIP_JSON"
            )
        )
    }

    /// A profile-wide Sponsored Products search-term report. `campaignId` is not
    /// a valid filter for `groupBy: searchTerm`, so callers filter rows to the
    /// campaign they care about client-side (rows carry `campaignId`).
    static func spSearchTerm(
        name: String,
        startDate: String,
        endDate: String
    ) -> ReportRequest {
        ReportRequest(
            name: name,
            startDate: startDate,
            endDate: endDate,
            configuration: Configuration(
                adProduct: "SPONSORED_PRODUCTS",
                groupBy: ["searchTerm"],
                columns: SearchTermReportRow.columns,
                reportTypeId: "spSearchTerm",
                timeUnit: "SUMMARY",
                format: "GZIP_JSON"
            )
        )
    }
}

extension KeyedDecodingContainer {
    /// Decodes an id that the reporting API returns as a number (campaign/ad group
    /// ids) but other APIs return as a string — normalize to `String`.
    func flexibleString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int64.self, forKey: key) { return String(value) }
        return nil
    }
}

/// A decoded row from a Sponsored Products search-term report.
struct SearchTermReportRow: Codable, Hashable {
    let searchTerm: String?
    let campaignId: String?
    let adGroupId: String?
    let clicks: Int?
    let cost: Double?
    let sales30d: Double?
    let purchases30d: Int? // orders

    static let columns = [
        "searchTerm", "campaignId", "adGroupId", "clicks",
        "cost", "sales30d", "purchases30d",
    ]

    init(
        searchTerm: String?, campaignId: String?, adGroupId: String?,
        clicks: Int?, cost: Double?, sales30d: Double?, purchases30d: Int?
    ) {
        self.searchTerm = searchTerm
        self.campaignId = campaignId
        self.adGroupId = adGroupId
        self.clicks = clicks
        self.cost = cost
        self.sales30d = sales30d
        self.purchases30d = purchases30d
    }

    enum CodingKeys: String, CodingKey {
        case searchTerm, campaignId, adGroupId, clicks, cost, sales30d, purchases30d
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        searchTerm = try container.decodeIfPresent(String.self, forKey: .searchTerm)
        campaignId = container.flexibleString(forKey: .campaignId)
        adGroupId = container.flexibleString(forKey: .adGroupId)
        clicks = try container.decodeIfPresent(Int.self, forKey: .clicks)
        cost = try container.decodeIfPresent(Double.self, forKey: .cost)
        sales30d = try container.decodeIfPresent(Double.self, forKey: .sales30d)
        purchases30d = try container.decodeIfPresent(Int.self, forKey: .purchases30d)
    }
}

/// `createAsyncReport` response.
struct CreateReportResponse: Decodable {
    let reportId: String
    let status: String?
}

/// Error body Amazon returns for a duplicate report request (HTTP 425). The
/// existing report's id is embedded in `detail`, e.g.
/// `"The Request is a duplicate of : 77af9ece-1c6b-47d1-a6b1-79910c35e661"`.
struct DuplicateReportError: Decodable {
    let code: String?
    let detail: String?

    /// The id of the already-registered report, parsed out of `detail`.
    var existingReportId: String? {
        guard let detail else { return nil }
        let token = detail.split(whereSeparator: { $0 == " " || $0 == ":" }).last.map(String.init)
        guard let token, token.contains("-") else { return nil }
        return token
    }
}

/// `getAsyncReport` status response.
struct ReportStatusResponse: Decodable {
    let reportId: String
    let status: String
    let url: String?
    let failureReason: String?
}

/// A decoded campaign row from a Sponsored Products report. Fields are optional
/// because the present columns depend on the requested `columns` / `timeUnit`.
struct CampaignReportRow: Codable, Hashable {
    let campaignId: String?
    let campaignName: String?
    let date: String?
    let impressions: Int?
    let clicks: Int?
    let cost: Double?
    let sales30d: Double?
    let purchases30d: Int?

    init(
        campaignId: String?, campaignName: String?, date: String?, impressions: Int?,
        clicks: Int?, cost: Double?, sales30d: Double?, purchases30d: Int?
    ) {
        self.campaignId = campaignId
        self.campaignName = campaignName
        self.date = date
        self.impressions = impressions
        self.clicks = clicks
        self.cost = cost
        self.sales30d = sales30d
        self.purchases30d = purchases30d
    }

    enum CodingKeys: String, CodingKey {
        case campaignId, campaignName, date, impressions, clicks, cost, sales30d, purchases30d
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        campaignId = container.flexibleString(forKey: .campaignId)
        campaignName = try container.decodeIfPresent(String.self, forKey: .campaignName)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        impressions = try container.decodeIfPresent(Int.self, forKey: .impressions)
        clicks = try container.decodeIfPresent(Int.self, forKey: .clicks)
        cost = try container.decodeIfPresent(Double.self, forKey: .cost)
        sales30d = try container.decodeIfPresent(Double.self, forKey: .sales30d)
        purchases30d = try container.decodeIfPresent(Int.self, forKey: .purchases30d)
    }
}

extension CampaignReportRow {
    static let summaryColumns = [
        "campaignId", "campaignName", "impressions", "clicks",
        "cost", "sales30d", "purchases30d",
    ]
    static let dailyColumns = ["campaignId", "date", "cost", "sales30d"]
}

/// Aggregated headline figures for the overview.
struct SpendMetrics: Hashable {
    var spend: Double = 0
    var sales: Double = 0

    /// ACOS = spend / sales, or `nil` when there are no sales.
    var acos: Double? {
        guard sales > 0 else { return nil }
        return spend / sales
    }
}

/// A campaign's spend + ACOS for the top-campaigns list.
struct CampaignSpend: Identifiable, Hashable {
    let campaignId: String
    let name: String
    let spend: Double
    let sales: Double

    var id: String {
        campaignId
    }

    var acos: Double? {
        sales > 0 ? spend / sales : nil
    }
}

/// One day of the spend trend.
struct DailySpend: Identifiable, Hashable {
    let date: Date
    let spend: Double

    var id: Date {
        date
    }
}
