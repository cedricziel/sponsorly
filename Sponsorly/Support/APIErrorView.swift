import SwiftUI
import UIKit

/// A reusable error view: a message and, when present, the raw Amazon response
/// body in a copyable/shareable monospaced "code" block — handy for pasting an
/// API error back for diagnosis.
struct APIErrorView: View {
    let message: String
    var responseBody: String?
    var retry: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Label("Request Failed", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let responseBody, !responseBody.isEmpty {
                    CodeBlock(text: prettyPrinted(responseBody))
                }
                if let retry {
                    Button("Retry", action: retry).buttonStyle(.bordered)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }

    private func prettyPrinted(_ body: String) -> String {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: object, options: [.prettyPrinted, .sortedKeys]
              ),
              let string = String(data: pretty, encoding: .utf8)
        else {
            return body
        }
        return string
    }
}

/// A monospaced, selectable code block with Copy and Share controls.
struct CodeBlock: View {
    let text: String
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Response").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = text
                    didCopy = true
                } label: {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                ShareLink(item: text) {
                    Image(systemName: "square.and.arrow.up").font(.caption)
                }
            }
            ScrollView([.horizontal, .vertical]) {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 280)
            .background(.background.secondary, in: .rect(cornerRadius: 8))
        }
    }
}

#Preview {
    APIErrorView(
        message: "Amazon returned HTTP 400.",
        responseBody: #"{"message":"Invalid column: sales30d for reportTypeId spSearchTerm","code":"400"}"#,
        retry: {}
    )
}
