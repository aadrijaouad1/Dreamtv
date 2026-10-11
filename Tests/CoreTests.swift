import Foundation

@main struct CoreTests {
    static func main() throws {
        var tests = 0
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            guard value() else { fatalError("FAIL: " + name) }
            tests += 1; print("PASS: " + name)
        }
        let input = "\u{FEFF}#EXTM3U\r\n#EXTINF:-1 group-title=\"News, world\" tvg-logo=\"https://x.test/a.png\",القناة\r\nrelative.m3u8\r\n#EXTINF:-1 group-title=\"أفلام\",Movie\nhttps://x.test/movie.mp4\n"
        let list = M3U.parse(input, base: URL(string: "https://x.test/dir/list.m3u")!)
        check(list.count == 2, "UTF-8 BOM, Arabic, CRLF")
        check(list[0].group == "News, world" && list[0].name == "القناة", "Quoted comma metadata")
        check(list[0].url == "https://x.test/dir/relative.m3u8", "Relative URL resolution")
        check(list[1].kind == .movie, "Movie classification")
        check(M3U.parse("<html>error</html>").isEmpty, "Reject HTML error page")
        check(M3U.parse("#EXTINF:-1,Bad\nfile:///etc/passwd\n#EXTINF:-1,Bad\njavascript:alert(1)").isEmpty, "Reject non-network schemes")
        check(M3U.parse("https://x.test/a\nhttps://x.test/a").count == 1, "Deduplicate stream URLs")
        check(M3U.parse("#EXTINF:-1,Special\n#EXTVLCOPT:http-user-agent=test\nhttps://x.test/a").first?.requiresHeaders == true, "Flag custom HTTP headers")
        check((try? webURL("https://user:password@x.test/a")) == nil, "Reject URL userinfo")
        let source = Source(mode: "xtream", url: "https://example.test:8443/base", username: "a/b", password: "p?#&")
        let api = try XtreamURL.api(source, action: "get_live_streams")
        let parts = URLComponents(url: api, resolvingAgainstBaseURL: false)!
        check(parts.path == "/base/player_api.php", "Preserve provider base path")
        check(parts.queryItems?.first(where: { $0.name == "password" })?.value == source.password, "Escape query credentials")
        let stream = try XtreamURL.stream(source, kind: .live, id: "42", ext: "m3u8")
        check(stream.contains("a%2Fb/p%3F%23%26/42.m3u8"), "Escape stream credentials as path segments")
        check((try? XtreamURL.stream(source, kind: .live, id: "../42", ext: "m3u8")) == nil, "Reject invalid provider IDs")
        var license = License(activated: false, paired: false, lifetime: false, blocked: false, serverTime: 1000, checkedAt: 1000, trialEnd: 2000, licenseEnd: 0)
        check(license.allows(at: 1999) && !license.allows(at: 2000), "Trial expiration boundary")
        check(!license.allows(at: 999), "Reject clock before server observation")
        license.activated = true; license.lifetime = true
        check(license.allows(at: 1001) && !license.allows(at: 1000 + 7 * 86400), "Paid offline grace boundary")
        license.blocked = true
        check(!license.allows(at: 1001), "Revocation denies playback")
        license.blocked = false; license.lifetime = false; license.licenseEnd = 3000
        check(license.allows(at: 2999) && !license.allows(at: 3000), "Paid subscription expiration")
        let large = (0..<35000).map { "#EXTINF:-1 group-title=\"TV\",Channel \($0)\nhttps://test.invalid/\($0).m3u8" }.joined(separator: "\n")
        check(M3U.parse(large).count == 35000, "35,000 channel catalogue")
        print("\(tests) core checks passed")
    }
}
