import AmazonAdsCore
import Foundation
import Network

/// Minimal loopback HTTP server that captures a single OAuth redirect on
/// `127.0.0.1:<port>/callback` and returns the full callback URL (so the
/// caller can verify `state` and extract `code`).
///
/// Bound to the loopback interface only — never exposed on the LAN, and it
/// doesn't trigger the local-network privacy prompt.
actor LoopbackRedirectServer {
    private let port: UInt16
    private let htmlProvider: OAuthHTMLProvider
    private var listener: NWListener?
    private var connection: NWConnection?
    private var isRunning = false
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var callbackContinuation: CheckedContinuation<URL, Error>?

    init(port: UInt16, htmlProvider: OAuthHTMLProvider = DefaultOAuthHTMLProvider()) {
        self.port = port
        self.htmlProvider = htmlProvider
    }

    /// Bind and start listening. Resolves once the listener is ready.
    func start() async throws {
        guard !isRunning else { return }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw LWAError.invalidResponse
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterfaceType = .loopback

        guard let listener = try? NWListener(using: parameters, on: nwPort) else {
            throw LWAError.invalidResponse
        }
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.handle(connection) }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            readyContinuation = continuation
            listener.stateUpdateHandler = { [weak self] state in
                Task { await self?.onListenerState(state) }
            }
            listener.start(queue: .main)
        }
    }

    /// Wait for the redirect and return the full callback URL.
    func waitForCallback() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            callbackContinuation = continuation
        }
    }

    func stop() {
        connection?.cancel()
        connection = nil
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: - Private

    private func onListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isRunning = true
            readyContinuation?.resume()
            readyContinuation = nil
        case let .failed(error):
            readyContinuation?.resume(throwing: error)
            readyContinuation = nil
        default:
            break
        }
    }

    private func handle(_ connection: NWConnection) {
        self.connection = connection
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            Task { await self?.onReceive(data: data, error: error) }
        }
    }

    private func onReceive(data: Data?, error: Error?) {
        if let error {
            finish(.failure(error))
            return
        }
        guard let data,
              let request = String(data: data, encoding: .utf8),
              let requestLine = request.components(separatedBy: "\r\n").first,
              requestLine.hasPrefix("GET ")
        else {
            send(html: htmlProvider.errorHTML(message: "Invalid request"), status: 400)
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2, parts[1].hasPrefix("/callback") else {
            send(html: htmlProvider.errorHTML(message: "Unexpected callback"), status: 404)
            return
        }

        guard let url = URL(string: "http://localhost:\(port)\(parts[1])") else {
            send(html: htmlProvider.errorHTML(message: "Malformed callback"), status: 400)
            return
        }

        // Hand the whole URL to the caller; it validates state and maps errors.
        send(html: htmlProvider.successHTML(), status: 200)
        finish(.success(url))
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            stop()
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        callbackContinuation?.resume(with: result)
        callbackContinuation = nil
    }

    private func send(html: String, status: Int) {
        let reason = status == 200 ? "OK" : (status == 404 ? "Not Found" : "Bad Request")
        let response = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r
        \(html)
        """
        guard let data = response.data(using: .utf8) else { return }
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }
}
