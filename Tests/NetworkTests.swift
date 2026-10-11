import Foundation

@main struct NetworkTests {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Pass the local fixture URL") }
        let root = CommandLine.arguments[1]
        guard root.hasPrefix("http://127.0.0.1:") else { fatalError("Tests only use loopback fixtures") }
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            guard value() else { fatalError("FAIL: " + name) }
            checks += 1; print("PASS: " + name)
        }
        let source = Source(mode: "xtream", url: root, username: "fixture-user", password: "fixture-password")
        let items = try await Provider.load(source)
        check(items.count == 3, "Xtream live, movie and series catalogue")
        check(items.first(where: { $0.kind == .live })?.url.hasSuffix(".m3u8") == true, "iOS HLS live endpoint")
        check(items.first(where: { $0.kind == .series })?.seriesRoot == true, "Series root navigation")
        let episodes = try await Provider.episodes(source, id: "3")
        check(episodes.map(\.episode) == [1, 2], "Episodes ordered by season and number")
        let guide = try await Provider.epg(source, id: "1")
        check(guide.contains("Programme") && guide.contains("Description"), "EPG base64 decoding")
        let list = try await Provider.load(Source(mode: "m3u", url: root + "/redirect"))
        check(list.first?.url == root + "/video.m3u8", "Redirect and relative playlist URL")
        do { _ = try await HTTP.load(URL(string: root + "/oversize")!, limit: 1024); fatalError("Size cap not enforced") }
        catch { checks += 1; print("PASS: streamed response size cap") }
        do { _ = try await HTTP.load(URL(string: root + "/redirect")!, bearer: "fixture-only"); fatalError("Authenticated redirect allowed") }
        catch { checks += 1; print("PASS: authenticated redirect denied") }
        do { _ = try await Provider.load(Source(mode: "m3u", url: root + "/html")); fatalError("HTML accepted as playlist") }
        catch { checks += 1; print("PASS: server error HTML rejected") }
        let license = try Site.license(["server_time": 1000, "activated": true, "paired": true, "lifetime": true, "blocked": false])
        check(license.allows(at: 1001) && license.paired, "Website license response mapping")
        print("\(checks) network checks passed")
    }
}
