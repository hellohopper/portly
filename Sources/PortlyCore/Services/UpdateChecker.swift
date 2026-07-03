import Foundation

public enum UpdateChecker {
    public struct UpdateInfo {
        public let version: String
        public let url: URL
        /// Direct download URL for the release's Portly.dmg asset, when published.
        /// Powers in-app "download and install"; falls back to opening `url` when nil.
        public let dmgURL: URL?
    }

    private static let releasesAPIURL = URL(string: "https://api.github.com/repos/hellohopper/portly/releases/latest")!

    public static func checkForUpdate(currentVersion: String) async -> UpdateInfo? {
        var request = URLRequest(url: releasesAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let htmlURLString = json["html_url"] as? String,
              let htmlURL = URL(string: htmlURLString) else { return nil }

        let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        guard isVersion(latestVersion, newerThan: currentVersion) else { return nil }

        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmgAsset = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
        let dmgURL = (dmgAsset?["browser_download_url"] as? String).flatMap(URL.init(string:))

        return UpdateInfo(version: latestVersion, url: htmlURL, dmgURL: dmgURL)
    }

    /// Numeric, component-wise comparison (so "0.10.0" correctly beats "0.9.0",
    /// unlike a plain string comparison).
    public static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let lhsParts = lhs.split(separator: ".").compactMap { Int($0) }
        let rhsParts = rhs.split(separator: ".").compactMap { Int($0) }
        let count = max(lhsParts.count, rhsParts.count)

        for index in 0..<count {
            let lhsValue = index < lhsParts.count ? lhsParts[index] : 0
            let rhsValue = index < rhsParts.count ? rhsParts[index] : 0
            if lhsValue != rhsValue { return lhsValue > rhsValue }
        }
        return false
    }
}
