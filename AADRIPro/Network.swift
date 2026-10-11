import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// A bounded request. No credentials/cookies are kept in URL caches or diagnostics.
private final class Transfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<(Data, URL), Error>?
    private var bytes = Data()
    private var finalURL: URL?
    private var failure: Error?
    private let limit: Int
    private let noRedirect: Bool
    private var session: URLSession?
    init(limit: Int, noRedirect: Bool) { self.limit = limit; self.noRedirect = noRedirect }
    func start(_ request: URLRequest, continuation: CheckedContinuation<(Data, URL), Error>) {
        self.continuation = continuation
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 90
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
        self.session = session
        session.dataTask(with: request).resume()
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, let url = response.url else { completionHandler(.cancel); return }
        finalURL = url
        if response.expectedContentLength > Int64(limit) { failure = AppFailure("الملف أكبر من الحد المسموح / File too large"); completionHandler(.cancel); return }
        if !(200...299).contains(http.statusCode) {
            failure = AppFailure("HTTP \(http.statusCode)")
            // Website JSON errors are needed to distinguish a blocked identity.
            if noRedirect && http.statusCode == 403 { failure = nil }
            else { completionHandler(.cancel); return }
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard bytes.count + data.count <= limit else { failure = AppFailure("الملف أكبر من الحد المسموح / File too large"); dataTask.cancel(); return }
        bytes.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard !noRedirect, let url = request.url, (try? webURL(url.absoluteString)) != nil else {
            failure = AppFailure("إعادة توجيه غير مسموحة / Redirect denied"); completionHandler(nil); return
        }
        completionHandler(request)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let callback = continuation; continuation = nil
        if let failure { callback?.resume(throwing: failure) }
        else if error != nil { callback?.resume(throwing: AppFailure("تعذر الاتصال بالخادم / Connection failed")) }
        else if let finalURL { callback?.resume(returning: (bytes, finalURL)) }
        else { callback?.resume(throwing: AppFailure("Empty response")) }
        session.finishTasksAndInvalidate(); self.session = nil
    }
}
enum HTTP {
    static func load(_ url: URL, body: [String: Any]? = nil, bearer: String? = nil, limit: Int = 150 * 1024 * 1024) async throws -> (Data, URL) {
        _ = try webURL(url.absoluteString)
        var request = URLRequest(url: url)
        request.setValue("AADRI-PRO-iOS/0.1.0", forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let bearer { request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
        return try await withCheckedThrowingContinuation { continuation in
            let transfer = Transfer(limit: limit, noRedirect: bearer != nil)
            transfer.start(request, continuation: continuation)
        }
    }
    static func json(_ url: URL) async throws -> Any {
        let (data, _) = try await load(url)
        return try JSONSerialization.jsonObject(with: data)
    }
}
enum Provider {
    static func api(_ source: Source, _ action: String = "", extra: [String: String] = [:]) async throws -> Any {
        try await HTTP.json(XtreamURL.api(source, action: action, extra: extra))
    }
    static func load(_ source: Source) async throws -> [Media] {
        if source.mode == "xtream" {
            guard let auth = try await api(source) as? [String: Any],
                  let user = auth["user_info"] as? [String: Any], string(user["auth"]) == "1" else { throw AppFailure("بيانات Xtream غير صحيحة / Authentication failed") }
            var result: [Media] = []
            for kind in MediaKind.allCases {
                let action = kind == .live ? "get_live_streams" : kind == .movie ? "get_vod_streams" : "get_series"
                let categoryAction = kind == .live ? "get_live_categories" : kind == .movie ? "get_vod_categories" : "get_series_categories"
                guard let categories = try await api(source, categoryAction) as? [[String: Any]],
                      let rows = try await api(source, action) as? [[String: Any]] else { throw AppFailure("قائمة Xtream غير صالحة / Invalid catalogue") }
                var map: [String: String] = [:]
                for row in categories { map[string(row["category_id"])] = string(row["category_name"]) }
                var seen = Set<String>()
                for row in rows {
                    let id = string(row[kind == .series ? "series_id" : "stream_id"])
                    guard !id.isEmpty, id.allSatisfy(\.isNumber), seen.insert(id).inserted else { continue }
                    // AVPlayer uses HLS, not the continuous MPEG-TS endpoint used on Windows.
                    let ext = kind == .live ? "m3u8" : (string(row["container_extension"]).isEmpty ? "mp4" : string(row["container_extension"]))
                    let url = kind == .series ? "" : try XtreamURL.stream(source, kind: kind, id: id, ext: ext)
                    result.append(Media(id: kind.rawValue + ":" + id, name: string(row["name"]), group: map[string(row["category_id"])] ?? "Other",
                                        logo: string(row[kind == .live ? "stream_icon" : "cover"] ?? row["stream_icon"]), kind: kind, url: url, providerID: id, seriesRoot: kind == .series))
                }
            }
            guard !result.isEmpty else { throw AppFailure("الاشتراك فارغ / Empty catalogue") }
            return result
        }
        let (data, url) = try await HTTP.load(webURL(source.url))
        return try await parse(data, base: url)
    }
    static func parse(_ data: Data, base: URL? = nil) async throws -> [Media] {
        guard data.count <= 150 * 1024 * 1024 else { throw AppFailure("الحد الأقصى 150 MB") }
        return try await Task.detached(priority: .userInitiated) {
            guard let text = String(data: data, encoding: .utf8) else { throw AppFailure("الملف يجب أن يكون UTF-8 / Invalid text encoding") }
            let items = M3U.parse(text, base: base)
            guard !items.isEmpty else { throw AppFailure("لم نعثر على قنوات داخل الملف / No streams found") }
            return items
        }.value
    }
    static func episodes(_ source: Source, id: String) async throws -> [Media] {
        guard let data = try await api(source, "get_series_info", extra: ["series_id": id]) as? [String: Any],
              let seasons = data["episodes"] as? [String: Any] else { throw AppFailure("لا توجد حلقات / No episodes") }
        var result: [Media] = []
        for (season, raw) in seasons {
            guard let rows = raw as? [[String: Any]] else { continue }
            for row in rows {
                let episodeID = string(row["id"])
                guard !episodeID.isEmpty, episodeID.allSatisfy(\.isNumber) else { continue }
                let ext = string(row["container_extension"])
                result.append(Media(id: "episode:" + episodeID, name: string(row["title"]), kind: .series,
                    url: try XtreamURL.stream(source, kind: .series, id: episodeID, ext: ext.isEmpty ? "mp4" : ext), providerID: episodeID,
                    season: integer(row["season"]) == 0 ? (Int(season) ?? 0) : integer(row["season"]), episode: integer(row["episode_num"])))
            }
        }
        return result.sorted { $0.season == $1.season ? $0.episode < $1.episode : $0.season < $1.season }
    }
    static func epg(_ source: Source, id: String) async throws -> String {
        let data = try await api(source, "get_short_epg", extra: ["stream_id": id, "limit": "8"]) as? [String: Any]
        let rows = data?["epg_listings"] as? [[String: Any]] ?? []
        func decode(_ input: Any?) -> String {
            let text = string(input)
            return Data(base64Encoded: text).flatMap { String(data: $0, encoding: .utf8) } ?? text
        }
        return rows.map { string($0["start"]) + " — " + string($0["end"]) + "\n" + decode($0["title"]) + "\n" + decode($0["description"]) }.joined(separator: "\n\n")
    }
}
struct SiteFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    var blocked: Bool { message.lowercased().contains("blocked") }
    var mismatch: Bool { message.lowercased().contains("identity mismatch") }
}
enum Site {
    static func request(_ endpoint: String, identity: Identity, profile: Profile, active: Bool, channel: String, extra: [String: Any] = [:]) async throws -> [String: Any] {
        guard ["device.php", "playlist.php", "delivery.php", "recover.php"].contains(endpoint) else { throw AppFailure("Invalid endpoint") }
        var body: [String: Any] = ["mac": identity.mac, "recovery_proof": identity.proof,
            "delivery_protocol": 1, "removal_protocol": 1, "telemetry_protocol": 1,
            "app_active": active, "current_channel": String(channel.prefix(200)), "device_type": "phone",
            "device_model": "iPhone / iPad", "client_platform": "iOS", "client_version": "0.1.0",
            "deleted_playlist_ids": Array(profile.deletedSite.prefix(100)), "deleted_local_playlist_ids": Array(profile.deletedLocal.prefix(100))]
        if endpoint == "device.php" && profile.shareCatalog {
            body["local_catalog_protocol"] = 1
            body["local_playlists"] = profile.accounts.filter { $0.remote == nil && $0.source.mode != "file" }.map { account in
                ["id": account.id, "name": account.name, "input_mode": account.source.mode == "xtream" ? "xtream" : "m3u",
                 "url": account.source.mode == "m3u" ? account.source.url : "", "server": account.source.mode == "xtream" ? account.source.url : "", "username": account.source.username]
            }
        }
        extra.forEach { body[$0.key] = $0.value }
        let (data, _) = try await HTTP.load(URL(string: "https://aadripro.com/api/" + endpoint)!, body: body, bearer: identity.token, limit: 2 * 1024 * 1024)
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AppFailure("استجابة الموقع غير صالحة / Invalid website response") }
        guard result["ok"] as? Bool == true else { throw SiteFailure(message: String(string(result["error"]).prefix(180))) }
        return result
    }
    static func license(_ data: [String: Any]) throws -> License {
        let clock = Double(integer(data["server_time"]))
        guard clock > 0 else { throw AppFailure("Invalid server clock") }
        return License(activated: data["activated"] as? Bool == true, paired: data["paired"] as? Bool == true,
            lifetime: data["lifetime"] as? Bool == true, blocked: data["blocked"] as? Bool == true,
            serverTime: clock, checkedAt: Date().timeIntervalSince1970,
            trialEnd: Double(integer(data["trial_expires_at"])), licenseEnd: Double(integer(data["license_expires_at"])))
    }
}
