import AppKit
import SwiftUI

struct AboutView: View {
    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "AgentLimits"
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var copyrightString: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            Text(appName)
                .font(.title2)
                .bold()

            Text("Versione \(versionString)")
                .font(.callout)
                .foregroundStyle(.secondary)

            if !copyrightString.isEmpty {
                Text(copyrightString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                if let repoURL = URL(string: "https://github.com/istefox/counter") {
                    Link("github.com/istefox/counter", destination: repoURL)
                }
                if let websiteURL = URL(string: "https://istefox.dev") {
                    Link("istefox.dev", destination: websiteURL)
                }
            }
            .font(.callout)
        }
        .padding(24)
        .frame(width: 280)
    }
}
