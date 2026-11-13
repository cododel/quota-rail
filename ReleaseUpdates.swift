import Foundation
import SwiftUI

@MainActor
final class ReleaseUpdates: ObservableObject {
    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }

        let tag_name: String
        let assets: [Asset]
    }

    @Published private(set) var message: String?
    @Published private(set) var download: URL?
    @Published private(set) var checking = false

    let currentVersion: String = {
        let directory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        return (try? String(contentsOf: directory.appendingPathComponent("VERSION"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "0.0.0"
    }()

    func check() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        download = nil

        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/cododel/quota-rail/releases/latest")!)
            request.timeoutInterval = 15
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode
            if status == 404 {
                message = "No published release yet."
                return
            }
            guard status == 200 else { throw URLError(.badServerResponse) }
            let release = try JSONDecoder().decode(Release.self, from: data)
            guard let latest = Self.versionParts(String(release.tag_name.dropFirst())),
                  release.tag_name.hasPrefix("v"),
                  let current = Self.versionParts(currentVersion) else {
                throw URLError(.cannotParseResponse)
            }
            guard current.lexicographicallyPrecedes(latest) else {
                message = "Quota Rail is up to date."
                return
            }
            guard let asset = release.assets.first(where: { $0.name == "quota-rail-macos-arm64.zip" }),
                  asset.browser_download_url.scheme == "https",
                  asset.browser_download_url.host == "github.com",
                  asset.browser_download_url.path == "/cododel/quota-rail/releases/download/\(release.tag_name)/\(asset.name)" else {
                message = "The release archive is unavailable."
                return
            }
            download = asset.browser_download_url
            message = "Quota Rail \(release.tag_name) is available."
        } catch is CancellationError {
            return
        } catch {
            message = "Could not check GitHub for updates."
        }
    }

    private static func versionParts(_ version: String) -> [Int]? {
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = components.compactMap { Int($0) }
        guard components.count == 3, numbers.count == 3, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        return numbers
    }
}

struct ReleaseUpdateControls: View {
    @ObservedObject var updates: ReleaseUpdates

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(updates.checking ? "Checking for updates…" : "Check for Updates") {
                Task { await updates.check() }
            }
            .disabled(updates.checking)
            if let message = updates.message {
                Text(message).font(.caption)
            }
            if let download = updates.download {
                Link("Download Update", destination: download)
            }
        }
    }
}
