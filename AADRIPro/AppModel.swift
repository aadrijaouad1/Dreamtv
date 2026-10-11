import SwiftUI
import AVFoundation

@MainActor final class AppModel: ObservableObject {
    @Published var profile = Profile()
    @Published var identity: Identity?
    @Published var catalog: [Media] = []
    @Published var busy = false
    @Published var ready = false
    @Published var demo = false
    @Published var message = ""
    @Published var siteError = ""
    @Published var lastSync: Date?
    @Published var episodes: [Media] = []
    @Published var selectedSeries: Media?
    @Published var epgText = ""
    @Published var showEPG = false
    @Published var fullscreen = false
    let playback = Playback()
    private var vault: Vault?
    private var clockAnchor = ProcessInfo.processInfo.systemUptime
    private var timeAnchor = Date().timeIntervalSince1970
    private var started = false
    var foreground = true
    var account: Account? { profile.accounts.first { $0.id == profile.activeID } }
    var isArabic: Bool { profile.language == "ar" }
    func t(_ ar: String, _ en: String) -> String { isArabic ? ar : en }
    var effectiveTime: Double { max(max(Date().timeIntervalSince1970, profile.highClock), timeAnchor + max(0, ProcessInfo.processInfo.systemUptime - clockAnchor)) }
    var permitted: Bool { profile.license?.allows(at: effectiveTime) == true }
    var status: String {
        if demo { return t("وضع التجربة — محتوى محلي فقط", "Demo — local sample only") }
        guard let license = profile.license else { return t("بانتظار الاتصال بالموقع", "Waiting for website") }
        if license.blocked { return t("الجهاز موقوف", "Device blocked") }
        if !permitted { return t("يلزم الاتصال أو تفعيل الجهاز", "Connect or activate this device") }
        if license.lifetime { return t("مفعّل مدى الحياة", "Lifetime activation") }
        if license.activated { return t("التفعيل ساري", "Activation valid") }
        return t("الفترة التجريبية", "Trial period")
    }
    func bootstrap() async {
        guard !started else { return }; started = true
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            #if DEBUG
            ready = true; enterDemo(); return
            #endif
        }
        do {
            let storage = try Vault(); vault = storage
            identity = try await storage.identity()
            profile = try await storage.profile()
            timeAnchor = max(Date().timeIntervalSince1970, profile.highClock); clockAnchor = ProcessInfo.processInfo.systemUptime
            if let account { catalog = try await storage.catalog(account.snapshotID) }
            ready = true
            await sync()
        } catch {
            message = t("تعذر قراءة البيانات المحفوظة. لم يتم حذفها. ", "Saved data could not be read; it was preserved. ") + error.localizedDescription
        }
    }
    func persist() async {
        guard !demo, let vault, ready else { return }
        profile.highClock = effectiveTime
        do { try await vault.save(profile) } catch { message = t("تعذر حفظ التغييرات: ", "Could not save: ") + error.localizedDescription }
    }
    func enterDemo() {
        guard !busy else { return }
        playback.stop(); fullscreen = false
        guard let url = Bundle.main.url(forResource: "sample", withExtension: "mp4") else { message = "Missing bundled demo video"; return }
        demo = true
        catalog = [Media(id: "demo-live", name: "قناة تجريبية • Sample", group: "DEMO", kind: .live, url: url.absoluteString),
                   Media(id: "demo-movie", name: "فيديو تجريبي • Sample", group: "DEMO", kind: .movie, url: url.absoluteString),
                   Media(id: "demo-series", name: "حلقة تجريبية • Sample", group: "DEMO", kind: .series, url: url.absoluteString)]
    }
    func leaveDemo() async {
        guard !busy else { return }
        playback.stop(); demo = false; catalog = []
        do { if let account, let vault { catalog = try await vault.catalog(account.snapshotID) } }
        catch { message = error.localizedDescription }
        await sync()
    }
    private func site(_ endpoint: String, extra: [String: Any] = [:]) async throws -> [String: Any] {
        guard let identity else { throw AppFailure("Device identity unavailable") }
        return try await Site.request(endpoint, identity: identity, profile: profile, active: foreground,
                                      channel: playback.item?.name ?? "", extra: extra)
    }
    func sync() async {
        guard ready, !demo, !busy, let vault else { return }
        busy = true; defer { busy = false }
        do {
            let response: [String: Any]
            do { response = try await site("device.php") }
            catch let error as SiteFailure where error.mismatch {
                let restored = try await site("recover.php")
                let token = string(restored["token"]), mac = string(restored["mac"])
                guard token.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                      mac.range(of: "^([A-F0-9]{2}:){5}[A-F0-9]{2}$", options: .regularExpression) != nil,
                      var identity else { throw AppFailure("Invalid identity recovery") }
                identity.token = token; identity.mac = mac
                try await vault.saveIdentity(identity); self.identity = identity
                response = try await site("device.php")
            }
            profile.license = try Site.license(response)
            timeAnchor = max(effectiveTime, profile.license!.serverTime); clockAnchor = ProcessInfo.processInfo.systemUptime
            profile.highClock = effectiveTime
            try await vault.save(profile)
            try await applyRemovals(response)
            lastSync = Date(); siteError = ""
            enforceLicense()
            guard profile.license?.paired == true, permitted else { return }
            let listing = try await site("playlist.php")
            try await applyRemovals(listing)
            guard let rows = listing["playlists"] as? [[String: Any]], rows.count <= 6 else { throw AppFailure("Invalid remote subscriptions") }
            var receipts: [[String: Any]] = []
            for row in rows {
                let id = string(row["id"]), version = integer(row["version"]), url = string(row["url"])
                guard id.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil,
                      version >= 1, (try? webURL(url)) != nil, !profile.hiddenRemote.contains(id) else { continue }
                let remote = RemotePlaylist(id: id, name: string(row["name"]), version: version, url: url)
                if let index = profile.accounts.firstIndex(where: { $0.remote?.id == id }) {
                    let saved = profile.accounts[index]
                    if saved.remote?.version != version {
                        profile.accounts[index].offer = remote
                        try await vault.save(profile); continue
                    }
                    if let existing = try? await vault.catalog(saved.snapshotID), !existing.isEmpty {
                        receipts.append(["id": id, "version": version, "status": "received"]); continue
                    }
                }
                do {
                    if !profile.accounts.contains(where: { $0.remote?.id == id }) && profile.accounts.count >= 6 { throw AppFailure("Capacity limit") }
                    let source = Source(mode: "m3u", url: url)
                    let items = try await Provider.load(source)
                    var next = profile.accounts.first { $0.remote?.id == id } ?? Account(name: remote.name, source: source)
                    next.name = remote.name; next.source = source; next.remote = remote
                    try await commit(next, items: items)
                    receipts.append(["id": id, "version": version, "status": "received"])
                } catch { receipts.append(["id": id, "version": version, "status": "failed", "error_code": "download_failed"]) }
            }
            if !receipts.isEmpty { _ = try await site("delivery.php", extra: ["receipts": receipts]) }
        } catch {
            if let error = error as? SiteFailure, error.blocked {
                if profile.license == nil { profile.license = License(activated: false, paired: false, lifetime: false, blocked: true, serverTime: 0, checkedAt: 0, trialEnd: 0, licenseEnd: 0) }
                profile.license?.blocked = true
                try? await vault.save(profile)
            }
            siteError = error.localizedDescription
            enforceLicense()
        }
    }
    private func applyRemovals(_ response: [String: Any]) async throws {
        for id in response["removed_playlist_ids"] as? [String] ?? [] {
            if let account = profile.accounts.first(where: { $0.remote?.id == id }) { try await removeStored(account) }
            if !profile.deletedSite.contains(id) { profile.deletedSite.append(id) }
        }
        for id in response["removed_local_playlist_ids"] as? [String] ?? [] {
            if let account = profile.accounts.first(where: { $0.remote == nil && $0.id == id }) { try await removeStored(account) }
            if !profile.deletedLocal.contains(id) { profile.deletedLocal.append(id) }
        }
        if let ids = response["removed_playlist_ids"] as? [String] { profile.deletedSite = profile.deletedSite.filter { ids.contains($0) } }
        if let ids = response["removed_local_playlist_ids"] as? [String] { profile.deletedLocal = profile.deletedLocal.filter { ids.contains($0) } }
        try await vault?.save(profile)
    }
    private func commit(_ account: Account, items: [Media]) async throws {
        guard let vault else { throw AppFailure("Storage unavailable") }
        var account = account
        let old = profile.accounts.first { $0.id == account.id }
        if old == nil && profile.accounts.count >= 6 { throw AppFailure("الحد الأقصى 6 اشتراكات / Maximum 6 subscriptions") }
        account.snapshotID = UUID().uuidString; account.count = items.count
        try await vault.put(account.snapshotID, items: items)
        var next = profile
        if let index = next.accounts.firstIndex(where: { $0.id == account.id }) { next.accounts[index] = account }
        else { next.accounts.append(account) }
        if next.activeID.isEmpty { next.activeID = account.id }
        do { try await vault.save(next) }
        catch { try? await vault.remove(account.snapshotID); throw error }
        profile = next
        if next.activeID == account.id { catalog = items }
        if let old { try? await vault.remove(old.snapshotID) }
    }
    func add(name: String, source: Source, data: Data? = nil) async -> Bool {
        guard ready, !busy, !demo else { return false }
        busy = true; defer { busy = false }
        do {
            guard profile.accounts.count < 6 else { throw AppFailure("الحد الأقصى 6 اشتراكات / Maximum 6 subscriptions") }
            let items: [Media]
            if let data { items = try await Provider.parse(data) } else { items = try await Provider.load(source) }
            let value = Account(name: name.isEmpty ? "Playlist" : String(name.prefix(80)), source: source)
            try await commit(value, items: items)
            return true
        } catch { message = error.localizedDescription; return false }
    }
    func select(_ account: Account) async {
        guard !busy, !demo, let vault else { return }
        busy = true; defer { busy = false }
        do {
            let items = try await vault.catalog(account.snapshotID)
            var next = profile; next.activeID = account.id; try await vault.save(next)
            playback.stop(); profile = next; catalog = items; selectedSeries = nil
        } catch { message = error.localizedDescription }
    }
    func reload(_ old: Account) async {
        guard !busy, !demo else { return }
        if old.source.mode == "file" { message = t("أعد استيراد الملف لتحديثه", "Import the updated file again"); return }
        busy = true; defer { busy = false }
        do {
            var next = old
            if let offer = old.offer { next.source = Source(mode: "m3u", url: offer.url); next.remote = offer; next.offer = nil }
            let items = try await Provider.load(next.source)
            try await commit(next, items: items)
            if let remote = next.remote {
                _ = try await site("delivery.php", extra: ["receipts": [["id": remote.id, "version": remote.version, "status": "received"]]])
            }
        } catch { message = error.localizedDescription }
    }
    private func removeStored(_ account: Account) async throws {
        guard let vault else { return }
        var next = profile
        next.accounts.removeAll { $0.id == account.id }; next.favorites.removeValue(forKey: account.id); next.history.removeValue(forKey: account.id)
        if next.activeID == account.id { next.activeID = next.accounts.first?.id ?? "" }
        let nextItems: [Media]
        if let active = next.accounts.first(where: { $0.id == next.activeID }) { nextItems = try await vault.catalog(active.snapshotID) } else { nextItems = [] }
        try await vault.save(next)
        if profile.activeID == account.id { playback.stop(); fullscreen = false }
        profile = next; catalog = nextItems
        try? await vault.remove(account.snapshotID)
    }
    func delete(_ account: Account) async {
        guard !busy, !demo else { return }; busy = true; defer { busy = false }
        do {
            if let remote = account.remote { profile.hiddenRemote.insert(remote.id) }
            try await removeStored(account)
        } catch { message = error.localizedDescription }
    }
    func play(_ item: Media) async {
        guard ready else { return }
        if demo {
            guard catalog.contains(item), URL(string: item.url)?.isFileURL == true else { return }
        } else {
            guard permitted else { message = t("اتصل بالموقع وفعّل الجهاز أولًا", "Connect and activate this device first"); return }
            guard catalog.contains(item) || episodes.contains(item) else { return }
        }
        if item.requiresHeaders { message = t("هذا البث يتطلب ترويسات خاصة غير مدعومة في هذه النسخة", "This stream requires custom headers not supported in this build"); return }
        if item.seriesRoot {
            guard let account, !busy else { return }; busy = true; defer { busy = false }
            do { episodes = try await Provider.episodes(account.source, id: item.providerID); selectedSeries = item }
            catch { message = error.localizedDescription }; return
        }
        let resume = demo || item.kind == .live ? 0 : profile.history[profile.activeID]?[item.id]?.seconds ?? 0
        playback.open(item, resume: resume)
    }
    func favorite(_ item: Media) async {
        guard !demo, !busy else { return }
        var set = profile.favorites[profile.activeID] ?? []
        if set.contains(item.id) { set.remove(item.id) } else { set.insert(item.id) }
        profile.favorites[profile.activeID] = set; await persist()
    }
    func isFavorite(_ item: Media) -> Bool { profile.favorites[profile.activeID]?.contains(item.id) == true }
    func checkpoint() async {
        enforceLicense()
        guard !demo, !busy, let item = playback.item, !profile.activeID.isEmpty else { return }
        var history = profile.history[profile.activeID] ?? [:]
        history[item.id] = Watched(seconds: item.kind == .live ? 0 : playback.position, updated: Date().timeIntervalSince1970)
        if history.count > 500 {
            let keep = Set(history.sorted { $0.value.updated > $1.value.updated }.prefix(500).map(\.key))
            history = history.filter { keep.contains($0.key) }
        }
        profile.history[profile.activeID] = history; await persist()
    }
    func enforceLicense() {
        if !demo && !permitted { playback.stop(); fullscreen = false }
    }
    func showGuide() async {
        guard let item = playback.item, let account, account.source.mode == "xtream", item.kind == .live, !busy else { return }
        busy = true; defer { busy = false }
        do { epgText = try await Provider.epg(account.source, id: item.providerID); showEPG = true }
        catch { message = error.localizedDescription }
    }
}
