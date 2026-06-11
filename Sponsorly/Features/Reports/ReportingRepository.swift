import Foundation

enum ReportError: LocalizedError {
    case http(status: Int, body: String?)
    case invalidResponse
    case generationFailed(String)
    case timedOut
    case missingDownloadURL
    case decompressionFailed

    var errorDescription: String? {
        switch self {
        case let .http(status, _): "Amazon returned HTTP \(status)."
        case .invalidResponse: "Received an unexpected response from Amazon."
        case let .generationFailed(reason): "Report generation failed: \(reason)"
        case .timedOut: "The report took too long to generate."
        case .missingDownloadURL: "The completed report had no download URL."
        case .decompressionFailed: "Couldn't read the downloaded report."
        }
    }
}

/// Drives the async Reporting API v3 lifecycle for the active profile:
/// create → poll until ready → download → decompress → decode.
actor ReportingRepository {
    private let scopedClient: ScopedClient
    private let urlSession: URLSession

    private static let createContentType = "application/vnd.createasyncreportrequest.v3+json"
    private static let getAccept = "application/vnd.getasyncreportresponse.v3+json"
    private static let maxPollAttempts = 12

    init(scopedClient: ScopedClient, urlSession: URLSession = .shared) {
        self.scopedClient = scopedClient
        self.urlSession = urlSession
    }

    /// Full lifecycle for campaign rows.
    func fetchCampaignRows(_ request: ReportRequest) async throws -> [CampaignReportRow] {
        try await fetchRows(request)
    }

    /// Full lifecycle for any report row type: create → poll → download → decode.
    func fetchRows<Row: Decodable & Sendable>(_ request: ReportRequest) async throws -> [Row] {
        let reportId = try await createReport(request)
        let downloadURL = try await pollUntilReady(reportId)
        return try await downloadRows(from: downloadURL)
    }

    func createReport(_ request: ReportRequest) async throws -> String {
        let url = scopedClient.baseURL.appendingPathComponent("reporting/reports")
        let body = try JSONEncoder().encode(request)
        let data = try await send(.post, url: url, contentType: Self.createContentType, body: body)
        return try JSONDecoder().decode(CreateReportResponse.self, from: data).reportId
    }

    func pollUntilReady(_ reportId: String) async throws -> URL {
        let url = scopedClient.baseURL.appendingPathComponent("reporting/reports/\(reportId)")
        for attempt in 0 ..< Self.maxPollAttempts {
            let data = try await send(.get, url: url, accept: Self.getAccept)
            let report = try JSONDecoder().decode(ReportStatusResponse.self, from: data)
            switch report.status.uppercased() {
            case "COMPLETED":
                guard let urlString = report.url, let downloadURL = URL(string: urlString) else {
                    throw ReportError.missingDownloadURL
                }
                return downloadURL
            case "FAILED":
                throw ReportError.generationFailed(report.failureReason ?? "unknown")
            default: // PENDING / PROCESSING
                try await Task.sleep(nanoseconds: Self.pollDelayNanos(attempt))
            }
        }
        throw ReportError.timedOut
    }

    private func downloadRows<Row: Decodable>(from url: URL) async throws -> [Row] {
        // Presigned S3 URL — no Amazon auth headers.
        let (data, response) = try await urlSession.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw ReportError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw ReportError.http(status: http.statusCode, body: httpResponseBody(data))
        }
        guard let json = ReportGunzip.decompress(data) else { throw ReportError.decompressionFailed }
        return try JSONDecoder().decode([Row].self, from: json)
    }

    // MARK: - HTTP

    private enum Method: String { case get = "GET", post = "POST" }

    private func send(
        _ method: Method,
        url: URL,
        contentType: String? = nil,
        accept: String? = nil,
        body: Data? = nil
    ) async throws -> Data {
        let token = try await scopedClient.tokenProvider()
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(scopedClient.clientID, forHTTPHeaderField: "Amazon-Advertising-API-ClientId")
        request.setValue(scopedClient.profileId, forHTTPHeaderField: "Amazon-Advertising-API-Scope")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        request.httpBody = body

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ReportError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw ReportError.http(status: http.statusCode, body: httpResponseBody(data))
        }
        return data
    }

    /// Capped, gently increasing backoff (~2s → 15s), ~110s total over 12 polls.
    nonisolated static func pollDelayNanos(_ attempt: Int) -> UInt64 {
        let seconds = min(2 + attempt * 2, 15)
        return UInt64(seconds) * 1_000_000_000
    }
}
