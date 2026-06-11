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

    /// A search-term report scoped to one campaign.
    static func spSearchTerm(
        name: String,
        startDate: String,
        endDate: String,
        campaignId: String
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
                format: "GZIP_JSON",
                filters: [Filter(field: "campaignId", values: [campaignId])]
            )
        )
    }
}

/// A decoded row from a Sponsored Products search-term report.
struct SearchTermReportRow: Decodable, Hashable {
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
}

/// `createAsyncReport` response.
struct CreateReportResponse: Decodable {
    let reportId: String
    let status: String?
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
