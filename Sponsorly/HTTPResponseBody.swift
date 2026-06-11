import Foundation

/// A short, log-friendly snippet of an HTTP error response body — used to surface
/// Amazon's actual error message when a request fails.
func httpResponseBody(_ data: Data, limit: Int = 2000) -> String? {
    guard let string = String(data: data, encoding: .utf8), !string.isEmpty else { return nil }
    return String(string.prefix(limit))
}

/// Extracts the raw Amazon response body from one of our HTTP errors, for display
/// in a copyable code block.
func apiResponseBody(from error: Error) -> String? {
    if let error = error as? ReportError, case let .http(_, body) = error { return body }
    if let error = error as? CampaignsError, case let .http(_, body) = error { return body }
    if let error = error as? AccountsError, case let .http(_, body) = error { return body }
    return nil
}
