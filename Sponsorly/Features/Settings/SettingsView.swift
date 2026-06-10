import SwiftUI

struct SettingsView: View {
    @State private var auth: AuthViewModel

    init(auth: AuthViewModel = AuthViewModel()) {
        _auth = State(initialValue: auth)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Amazon Ads Account") {
                    if auth.isSignedIn {
                        LabeledContent("Status") {
                            Label("Connected", systemImage: "checkmark.seal.fill")
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(.green)
                        }
                        Button("Sign Out", role: .destructive) {
                            Task { await auth.signOut() }
                        }
                    } else {
                        Button {
                            Task { await auth.signIn() }
                        } label: {
                            HStack {
                                Text("Sign in with Amazon")
                                if auth.isBusy {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(auth.isBusy)
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.appVersion)
                }
            }
            .navigationTitle("Settings")
            .task { await auth.restore() }
            .alert(
                "Sign-in failed",
                isPresented: Binding(
                    get: { auth.errorMessage != nil },
                    set: { if !$0 { auth.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(auth.errorMessage ?? "")
            }
        }
    }
}

private extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }
}

#Preview("Signed out") {
    SettingsView(auth: .previewModel(signedIn: false))
}

#Preview("Signed in") {
    SettingsView(auth: .previewModel(signedIn: true))
}
