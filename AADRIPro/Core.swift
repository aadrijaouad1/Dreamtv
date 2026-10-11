import Foundation

struct AppFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
enum MediaKind: String, Codable, CaseIterable { case live, movie, series }
struct Media: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var group: String = "Other"
    var logo: String = ""
    var kind: MediaKind = .live
    var url: String
    var providerID: String = ""
    var seriesRoot: Bool = false
    var season: Int = 0
    var episode: Int = 0
    var requiresHeaders: Bool = false
}
struct Source: Codable, Equatable {
    var mode: String = "m3u"
    var url: String = ""
    var username: String = ""
    var password: String = ""
}
struct RemotePlaylist: Codable, Equatable {
    var id: String
    var name: String
    var version: Int
    var url: String
}
struct Account: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var snapshotID = UUID().uuidString
    var name: String
    var source: Source
    var count: Int = 0
    var remote: RemotePlaylist? = nil
    var offer: RemotePlaylist? = nil
}
struct Watched: Codable {
    var seconds: Double
    var updated: Double
}
struct License: Codable {
    var activated: Bool
    var paired: Bool
    var lifetime: Bool
    var blocked: Bool
    var serverTime: Double
    var checkedAt: Double
    var trialEnd: Double
    var licenseEnd: Double
    func allows(at now: Double) -> Bool {
        guard !blocked else { return false }
        if activated { return now >= serverTime && now - serverTime < 7 * 86400 && (lifetime || now < licenseEnd) }
        return now >= serverTime && now < trialEnd
    }
}
struct Profile: Codable {
    var schema = 1
    var accounts: [Account] = []
    var activeID: String = ""
    var favorites: [String: Set<String>] = [:]
    var history: [String: [String: Watched]] = [:]
    var license: License? = nil
    var highClock: Double = 0
    var deletedSite: [String] = []
    var deletedLocal: [String] = []
    var hiddenRemote: Set<String> = []
    var language = "ar"
    var fit = "fill"
    var shareCatalog = false
}
func webURL(_ text: String) throws -> URL {
    guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
          url.host != nil, url.user == nil, url.password == nil else {
        throw AppFailure("أدخل رابط HTTP أو HTTPS صالحًا / Invalid URL")
    }
    return url
}
func integer(_ value: Any?) -> Int {
    if let n = value as? Int { return n }
    return Int(value as? String ?? "") ?? 0
}
func string(_ value: Any?) -> String {
    if let value = value as? String { return value }
    if let value = value as? NSNumber { return value.stringValue }
    return ""
}
enum M3U {
    static func parse(_ text: String, base: URL? = nil) -> [Media] {
        let pattern = try! NSRegularExpression(pattern: "([\\w-]+)=\"([^\"]*)\"")
        var items: [Media] = [], metadata: [String: String]? = nil
        var needsHeaders = false
        var seen = Set<String>()
        for raw in text.replacingOccurrences(of: "\u{FEFF}", with: "").components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("#EXTINF:") {
                var attrs: [String: String] = [:]
                let ns = line as NSString
                for m in pattern.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                    attrs[ns.substring(with: m.range(at: 1))] = ns.substring(with: m.range(at: 2))
                }
                var quoted = false
                for index in line.indices {
                    if line[index] == "\"" { quoted.toggle() }
                    if line[index] == "," && !quoted { attrs["name"] = String(line[line.index(after: index)...]); break }
                }
                metadata = attrs; needsHeaders = false; continue
            }
            if line.lowercased().hasPrefix("#extvlcopt:http-") { needsHeaders = true; continue }
            if line.hasPrefix("#") { continue }
            defer { metadata = nil; needsHeaders = false }
            if metadata == nil && !(line.lowercased().hasPrefix("http://") || line.lowercased().hasPrefix("https://")) { continue }
            guard let resolved = URL(string: line, relativeTo: base)?.absoluteURL,
                  let url = try? webURL(resolved.absoluteString) else { continue }
            guard seen.insert(url.absoluteString).inserted else { continue }
            let group = metadata?["group-title"] ?? "Other"
            let lower = (url.path + " " + group).lowercased()
            var kind: MediaKind = .live
            if lower.contains("/series/") || lower.contains("series") || lower.contains("مسلسل") { kind = .series }
            else if lower.contains("/movie/") || ["mp4", "mkv", "avi", "mov", "webm"].contains(url.pathExtension.lowercased()) || ["movies", "films", "vod", "أفلام"].contains(where: lower.contains) { kind = .movie }
            items.append(Media(id: url.absoluteString, name: metadata?["name"] ?? url.lastPathComponent,
                               group: group, logo: metadata?["tvg-logo"] ?? "", kind: kind,
                               url: url.absoluteString, requiresHeaders: needsHeaders))
        }
        return items
    }
}
enum XtreamURL {
    static func api(_ source: Source, action: String = "", extra: [String: String] = [:]) throws -> URL {
        let host = try webURL(source.url)
        var parts = URLComponents(url: host.appendingPathComponent("player_api.php"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "username", value: source.username), URLQueryItem(name: "password", value: source.password)]
        if !action.isEmpty { parts.queryItems?.append(URLQueryItem(name: "action", value: action)) }
        for key in extra.keys.sorted() { parts.queryItems?.append(URLQueryItem(name: key, value: extra[key])) }
        guard let result = parts.url else { throw AppFailure("Invalid provider URL") }
        return result
    }
    static func stream(_ source: Source, kind: MediaKind, id: String, ext: String) throws -> String {
        guard !id.isEmpty, id.allSatisfy(\.isNumber) else { throw AppFailure("Invalid stream ID") }
        let safeExtension = ext.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        let host = try webURL(source.url)
        var parts = URLComponents(url: host, resolvingAgainstBaseURL: false)!
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let segments = [kind.rawValue, source.username, source.password, id + "." + safeExtension]
        parts.percentEncodedPath = parts.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty ? "" : parts.percentEncodedPath
        while parts.percentEncodedPath.hasSuffix("/") { parts.percentEncodedPath.removeLast() }
        parts.percentEncodedPath += "/" + segments.map { $0.addingPercentEncoding(withAllowedCharacters: allowed)! }.joined(separator: "/")
        parts.query = nil; parts.fragment = nil
        guard let result = parts.url else { throw AppFailure("Invalid stream URL") }
        return result.absoluteString
    }
}
