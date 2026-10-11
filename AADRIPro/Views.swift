import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

private let accent = Color(red: 0.13, green: 0.59, blue: 0.95)
private let panel = Color(red: 0.045, green: 0.095, blue: 0.15)
private let muted = Color(red: 0.57, green: 0.65, blue: 0.73)
private enum Sheet: String, Identifiable { case accounts, settings, activation; var id: String { rawValue } }
struct Backdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.05, blue: 0.08)
            RadialGradient(colors: [accent.opacity(0.23), .clear], center: .topLeading, startRadius: 5, endRadius: 650)
            RadialGradient(colors: [accent.opacity(0.14), .clear], center: .bottomTrailing, startRadius: 5, endRadius: 450)
        }.ignoresSafeArea()
    }
}
struct Brand: View {
    var large = false
    var body: some View {
        HStack(spacing: 8) {
            Image("Logo").resizable().scaledToFit().frame(width: large ? 48 : 28, height: large ? 48 : 28).clipShape(RoundedRectangle(cornerRadius: 7))
            (Text("AADRI").foregroundColor(.cyan) + Text(" PRO").foregroundColor(.white))
                .font(.system(size: large ? 42 : 21, weight: .heavy)).tracking(-1)
        }.environment(\.layoutDirection, .leftToRight)
    }
}
struct HomeTile: View {
    let title: String
    let symbol: String
    var primary = false
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: primary ? 62 : 34, weight: .light)).foregroundStyle(.cyan)
            Text(title).font(primary ? .title3.weight(.semibold) : .subheadline.weight(.medium)).foregroundColor(.white)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(18)
            .background(LinearGradient(colors: [primary ? accent.opacity(0.25) : panel, panel], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(primary ? accent : Color.white.opacity(0.14), lineWidth: primary ? 2 : 1))
            .shadow(color: primary ? accent.opacity(0.18) : .clear, radius: 15)
    }
}
struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: Sheet?
    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    Backdrop()
                    ScrollView {
                        VStack(spacing: 24) {
                            HStack {
                                Brand(); Spacer()
                                Button { sheet = .activation } label: {
                                    Image(systemName: model.lastSync == nil ? "wifi.exclamationmark" : "wifi").foregroundColor(model.lastSync == nil ? .orange : .cyan)
                                }.accessibilityLabel(model.t("حالة التفعيل", "Activation status"))
                            }.padding(.bottom, 10)
                            Brand(large: true).padding(.top, geo.size.width > 700 ? 4 : 18)
                            Rectangle().fill(LinearGradient(colors: [.clear, .cyan, .clear], startPoint: .leading, endPoint: .trailing)).frame(width: 260, height: 2)
                            Text(model.t("كل محتواك، في مكان واحد", "All your content, in one place")).font(.subheadline).foregroundColor(muted)
                            if geo.size.width > 700 {
                                HStack(spacing: 14) {
                                    tile(.live).frame(maxWidth: .infinity)
                                    middleTiles.frame(maxWidth: .infinity)
                                    options.frame(maxWidth: .infinity)
                                }.frame(height: 255).environment(\.layoutDirection, .leftToRight)
                            } else {
                                tile(.live).frame(height: 160)
                                middleTiles.frame(height: 235)
                                options
                            }
                            Text(model.status).font(.footnote).foregroundColor(muted).multilineTextAlignment(.center)
                            if !model.siteError.isEmpty && !model.demo { Text(model.siteError).font(.caption).foregroundColor(.orange).lineLimit(3) }
                            if model.busy { ProgressView(model.t("جارٍ التحميل…", "Loading…")).tint(.cyan) }
                            Button(model.t("إضافة اشتراك", "Add subscription")) { sheet = .accounts }
                                .buttonStyle(.borderedProminent).tint(accent).disabled(!model.ready || model.demo || model.busy)
                            Button(model.demo ? model.t("العودة إلى اشتراكاتي", "Return to my subscriptions") : model.t("تجربة المشغل بدون اشتراك", "Try the sample player")) {
                                if model.demo { Task { await model.leaveDemo() } } else { model.enterDemo() }
                            }.font(.footnote).disabled(!model.ready || model.busy).accessibilityIdentifier("demoMode")
                            HStack { Text("iOS 0.1.0"); Spacer(); Link("aadripro.com ↗", destination: URL(string: "https://aadripro.com")!) }.font(.caption).foregroundColor(muted)
                        }.padding(24).frame(maxWidth: 1150).frame(maxWidth: .infinity)
                    }
                }
            }.toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: String.self) { kind in BrowseView(kind: MediaKind(rawValue: kind) ?? .live, sports: kind == "sports", allFavorites: kind == "favorites") }
        }.tint(.cyan).preferredColorScheme(.dark)
            .environment(\.layoutDirection, model.isArabic ? .rightToLeft : .leftToRight)
            .sheet(item: $sheet) { value in
                NavigationStack {
                    Group {
                        switch value {
                        case .accounts: AccountsView()
                        case .settings: SettingsView()
                        case .activation: ActivationView()
                        }
                    }.toolbar { ToolbarItem(placement: .confirmationAction) { Button(model.t("تم", "Done")) { sheet = nil } } }
                }.preferredColorScheme(.dark).tint(.cyan).appErrors()
            }
            .fullScreenCover(isPresented: $model.fullscreen) { FullscreenPlayer(playback: model.playback).environmentObject(model) }
            .sheet(isPresented: $model.showEPG) {
                NavigationStack { ScrollView { Text(model.epgText.isEmpty ? model.t("لا توجد بيانات برامج", "No programme data") : model.epgText).frame(maxWidth: .infinity, alignment: .leading).padding() }
                    .navigationTitle("EPG").toolbar { Button(model.t("تم", "Done")) { model.showEPG = false } } }.preferredColorScheme(.dark)
            }
            .appErrors()
            .task {
                await model.bootstrap()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    if Task.isCancelled { break }
                    if scenePhase == .active { await model.checkpoint(); await model.sync() }
                }
            }
            .onChange(of: scenePhase) { phase in
                model.foreground = phase == .active
                if phase != .active { model.playback.player.pause(); Task { await model.checkpoint() } }
                else { Task { await model.sync() } }
            }
    }
    func tile(_ kind: MediaKind) -> some View {
        NavigationLink(value: kind.rawValue) {
            HomeTile(title: kind == .live ? model.t("القنوات المباشرة", "Live TV") : kind == .movie ? model.t("الأفلام", "Movies") : model.t("المسلسلات", "Series"),
                     symbol: kind == .live ? "play.tv" : kind == .movie ? "film" : "play.rectangle.on.rectangle", primary: kind == .live)
        }.buttonStyle(.plain).accessibilityIdentifier("home-" + kind.rawValue)
    }
    var middleTiles: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) { tile(.movie); tile(.series) }
            HStack(spacing: 10) {
                NavigationLink(value: "sports") { HomeTile(title: model.t("الرياضة", "Sports"), symbol: "sportscourt") }.buttonStyle(.plain)
                Button { sheet = .accounts } label: { HomeTile(title: model.t("الاشتراكات", "Playlists"), symbol: "list.bullet.rectangle") }.buttonStyle(.plain)
            }
        }
    }
    var options: some View {
        VStack(spacing: 10) {
            option(model.t("الإعدادات", "Settings"), icon: "gearshape") { sheet = .settings }
            option(model.t("تفاصيل الحساب", "Account details"), icon: "person.crop.circle") { sheet = .activation }
            option(model.t("تحديث الاشتراك", "Reload subscription"), icon: "arrow.clockwise") { if let account = model.account { Task { await model.reload(account) } } else { sheet = .accounts } }
            NavigationLink(value: "favorites") {
                HStack { Image(systemName: "star").frame(width: 24); Text(model.t("المفضلة", "Favorites")); Spacer() }
                    .font(.subheadline).padding(15).foregroundColor(.white).background(panel).clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.13)))
            }.buttonStyle(.plain)
        }.environment(\.layoutDirection, model.isArabic ? .rightToLeft : .leftToRight)
    }
    func option(_ text: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack { Image(systemName: icon).frame(width: 24); Text(text); Spacer() }.font(.subheadline).padding(15).frame(maxWidth: .infinity).foregroundColor(.white).background(panel).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.13))) }.buttonStyle(.plain)
    }
}
struct BrowseView: View {
    let kind: MediaKind
    var sports = false
    var allFavorites = false
    @EnvironmentObject var model: AppModel
    @State private var query = ""
    @State private var group = ""
    @State private var favoriteOnly = false
    @State private var recentOnly = false
    @State private var filtered: [Media] = []
    @State private var groups: [String] = []
    @State private var revision = 0
    @State private var page = 0
    private let pageSize = 100
    var title: String { allFavorites ? model.t("المفضلة", "Favorites") : sports ? model.t("الرياضة", "Sports") : kind == .live ? model.t("القنوات", "Live TV") : kind == .movie ? model.t("الأفلام", "Movies") : model.t("المسلسلات", "Series") }
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Backdrop()
                if geo.size.width > 740 {
                    HStack(alignment: .top, spacing: 18) {
                        results.frame(maxWidth: .infinity)
                        ScrollView { PlayerPanel(playback: model.playback) }.frame(width: geo.size.width * 0.46)
                    }.padding(18)
                } else {
                    VStack(spacing: 12) {
                        if model.playback.item != nil { ScrollView { PlayerPanel(playback: model.playback) }.frame(maxHeight: geo.size.height * 0.48) }
                        results
                    }.padding(14)
                }
            }
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: model.t("بحث…", "Search…"))
            .onReceive(model.$catalog) { _ in revision += 1 }
            .task(id: "\(revision)|\(query)|\(group)|\(favoriteOnly)|\(recentOnly)|\(model.profile.favorites[model.profile.activeID]?.count ?? 0)") { await filter() }
            .sheet(item: $model.selectedSeries) { series in
                NavigationStack {
                    List(model.episodes) { episode in
                        Button { model.selectedSeries = nil; Task { await model.play(episode) } } label: {
                            VStack(alignment: .leading) { Text(episode.name); Text("S\(episode.season) · E\(episode.episode)").font(.caption).foregroundColor(muted) }
                        }
                    }.navigationTitle(series.name).toolbar { Button(model.t("رجوع", "Back")) { model.selectedSeries = nil } }
                }.preferredColorScheme(.dark)
            }
    }
    var results: some View {
        VStack(spacing: 10) {
            HStack {
                Menu {
                    Button(model.t("كل المجموعات", "All groups")) { group = "" }
                    ForEach(groups, id: \.self) { value in Button(value) { group = value } }
                } label: { Label(group.isEmpty ? model.t("المجموعات", "Groups") : group, systemImage: "line.3.horizontal.decrease.circle").lineLimit(1) }
                Spacer()
                Button { favoriteOnly.toggle() } label: { Image(systemName: favoriteOnly ? "star.fill" : "star") }.accessibilityLabel(model.t("المفضلة", "Favorites"))
                Button { recentOnly.toggle() } label: { Image(systemName: recentOnly ? "clock.fill" : "clock") }.accessibilityLabel(model.t("الأخيرة", "Recent"))
            }.font(.subheadline).tint(.cyan)
            HStack { Text("\(filtered.count) " + model.t("عنصر", "items")); Spacer(); Text(model.demo ? "DEMO" : model.account?.name ?? "") }.font(.caption).foregroundColor(muted)
            if filtered.isEmpty {
                Spacer(); Label(model.t("لا توجد عناصر؛ أضف اشتراكًا أو جرّب العينة", "No items. Add a playlist or try the demo"), systemImage: "rectangle.stack").font(.subheadline).foregroundColor(muted).multilineTextAlignment(.center); Spacer()
            } else {
                ScrollView {
                    if kind == .live || allFavorites {
                        LazyVStack(spacing: 6) { mediaButtons }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 12)], spacing: 12) { mediaButtons }
                    }
                }
                HStack {
                    Button { page -= 1 } label: { Image(systemName: "chevron.left") }.disabled(page == 0)
                    Spacer(); Text("\(page + 1) / \(max(1, (filtered.count + pageSize - 1) / pageSize))").font(.caption); Spacer()
                    Button { page += 1 } label: { Image(systemName: "chevron.right") }.disabled((page + 1) * pageSize >= filtered.count)
                }.buttonStyle(.bordered).environment(\.layoutDirection, .leftToRight)
            }
        }
    }
    var mediaButtons: some View {
        ForEach(Array(filtered.dropFirst(page * pageSize).prefix(pageSize))) { item in
            Button { Task { await model.play(item) } } label: {
                if kind == .live || allFavorites {
                    MediaRow(item: item, favorite: model.isFavorite(item), selected: model.playback.item?.id == item.id)
                } else {
                    VStack(spacing: 0) {
                        AsyncImage(url: try? webURL(item.logo)) { image in image.resizable().scaledToFill() } placeholder: {
                            ZStack { panel; Image(systemName: item.kind == .movie ? "film" : "play.rectangle.on.rectangle").font(.largeTitle).foregroundColor(.cyan) }
                        }.frame(height: 174).clipped()
                        Text(item.name).font(.caption).lineLimit(2).frame(maxWidth: .infinity, minHeight: 44).padding(6)
                    }.foregroundColor(.white).background(panel).clipShape(RoundedRectangle(cornerRadius: 9))
                }
            }.buttonStyle(.plain).accessibilityIdentifier("media-" + (model.demo ? item.id : String(item.id.prefix(24))))
                .contextMenu { Button(model.t("تغيير المفضلة", "Toggle favorite")) { Task { await model.favorite(item) } } }
        }
    }
    func filter() async {
        if !query.isEmpty { try? await Task.sleep(nanoseconds: 200_000_000) }
        guard !Task.isCancelled else { return }
        let items = model.catalog, q = query, selectedGroup = group, favorites = model.profile.favorites[model.profile.activeID] ?? []
        let history = model.profile.history[model.profile.activeID] ?? [:], onlyFav = favoriteOnly, onlyRecent = recentOnly
        let mediaKind = kind, sportsOnly = sports, acrossKinds = allFavorites
        let result = await Task.detached(priority: .userInitiated) { () -> ([Media], [String]) in
            let base = items.filter { (acrossKinds || $0.kind == mediaKind) && (!sportsOnly || ($0.group + " " + $0.name).range(of: "sport|bein|رياض|دوري", options: [.regularExpression, .caseInsensitive]) != nil) }
            let categories = Array(Set(base.map(\.group))).sorted()
            var selected = base.filter { (selectedGroup.isEmpty || $0.group == selectedGroup) && (q.isEmpty || $0.name.localizedCaseInsensitiveContains(q)) && (!(onlyFav || acrossKinds) || favorites.contains($0.id)) && (!onlyRecent || history[$0.id] != nil) }
            if onlyRecent { selected.sort { (history[$0.id]?.updated ?? 0) > (history[$1.id]?.updated ?? 0) } }
            return (selected, categories)
        }.value
        guard !Task.isCancelled else { return }
        filtered = result.0; groups = result.1; page = 0
    }
}
struct MediaRow: View {
    let item: Media
    var favorite: Bool
    var selected: Bool
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: try? webURL(item.logo)) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: item.kind == .live ? "play.tv" : "film").font(.title2).foregroundColor(.cyan) }
                .frame(width: 48, height: 46).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) { Text(item.name).font(.subheadline).lineLimit(2); Text(item.group).font(.caption2).foregroundColor(muted).lineLimit(1) }
            Spacer(minLength: 3)
            if favorite { Image(systemName: "star.fill").foregroundColor(.cyan).font(.caption) }
            Image(systemName: "play.fill").font(.caption).foregroundColor(.cyan)
        }.padding(10).foregroundColor(.white).background(selected ? accent.opacity(0.2) : panel).clipShape(RoundedRectangle(cornerRadius: 9))
    }
}
struct AccountsView: View {
    @EnvironmentObject var model: AppModel
    @State private var add = false
    @State private var deleting: Account?
    var body: some View {
        List {
            if model.demo { Text(model.t("اخرج من وضع التجربة لإضافة اشتراكك", "Leave demo mode to add your playlist")) }
            ForEach(model.profile.accounts) { account in
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(account.name).font(.headline); Spacer(); if account.id == model.profile.activeID { Image(systemName: "checkmark.circle.fill").foregroundColor(.cyan) } }
                    Text("\(account.count) " + model.t("عنصر", "items")).font(.caption).foregroundColor(muted)
                    if account.offer != nil { Text(model.t("يوجد تحديث من الموقع", "Update available from website")).font(.caption).foregroundColor(.orange) }
                    HStack {
                        Button(model.t("اختيار", "Select")) { Task { await model.select(account) } }
                        Button(model.t("تحديث", "Reload")) { Task { await model.reload(account) } }
                        Spacer()
                        Button(role: .destructive) { deleting = account } label: { Image(systemName: "trash") }
                    }.buttonStyle(.bordered).disabled(model.busy || model.demo)
                }.padding(.vertical, 6)
            }
            Button { add = true } label: { Label(model.t("إضافة اشتراك", "Add subscription"), systemImage: "plus.circle") }
                .disabled(model.profile.accounts.count >= 6 || model.busy || !model.ready || model.demo)
            if model.busy { ProgressView(model.t("جارٍ التحميل…", "Loading…")) }
            Text(model.t("حتى 6 اشتراكات. تبقى القوائم والمفضلة محفوظة بعد تحديث التطبيق.", "Up to 6 subscriptions. Updating the app preserves playlists and favorites.")).font(.caption).foregroundColor(muted)
        }.navigationTitle(model.t("الاشتراكات", "Playlists"))
            .sheet(isPresented: $add) { NavigationStack { ImportView() }.preferredColorScheme(.dark).appErrors() }
            .confirmationDialog(model.t("حذف هذا الاشتراك من الجهاز؟", "Remove this playlist from this device?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button(model.t("حذف", "Remove"), role: .destructive) { if let account = deleting { Task { await model.delete(account) } }; deleting = nil }
            }
    }
}
struct ImportView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var mode = "m3u"
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var importer = false
    @State private var fileData: Data?
    @State private var fileName = ""
    var body: some View {
        Form {
            Picker(model.t("النوع", "Type"), selection: $mode) { Text("M3U URL").tag("m3u"); Text("Xtream").tag("xtream"); Text(model.t("ملف", "File")).tag("file") }.pickerStyle(.segmented)
            TextField(model.t("اسم الاشتراك", "Playlist name"), text: $name)
            if mode == "file" {
                Button(fileName.isEmpty ? model.t("اختيار M3U / M3U8", "Choose M3U / M3U8") : fileName) { importer = true }
            } else {
                TextField(mode == "xtream" ? "https://server:port" : "https://server/playlist.m3u", text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().environment(\.layoutDirection, .leftToRight)
            }
            if mode == "xtream" {
                TextField(model.t("اسم المستخدم", "Username"), text: $username).textInputAutocapitalization(.never).autocorrectionDisabled().environment(\.layoutDirection, .leftToRight)
                SecureField(model.t("كلمة المرور", "Password"), text: $password).environment(\.layoutDirection, .leftToRight)
            }
            Text(model.t("يدعم مشغل iOS بث HLS وملفات MP4 المتوافقة. روابط TS المباشرة والصيغ الأخرى تعتمد على مزود البث.", "The iOS player supports HLS and compatible MP4. Direct TS streams and other formats may need provider changes.")).font(.caption).foregroundColor(muted)
            Button(model.t("حفظ وتحميل", "Save and load")) {
                Task {
                    let success = await model.add(name: name, source: Source(mode: mode, url: url, username: username, password: password), data: mode == "file" ? fileData : nil)
                    if success { dismiss() }
                }
            }.disabled(model.busy || (mode == "file" ? fileData == nil : url.isEmpty) || (mode == "xtream" && (username.isEmpty || password.isEmpty)))
            if model.busy { ProgressView(model.t("تحميل الاشتراك…", "Loading playlist…")) }
        }.navigationTitle(model.t("اشتراك جديد", "New playlist")).disabled(model.busy)
            .interactiveDismissDisabled(model.busy)
            .toolbar { Button(model.t("إلغاء", "Cancel")) { dismiss() }.disabled(model.busy) }
            .fileImporter(isPresented: $importer, allowedContentTypes: [.item]) { result in
                Task {
                    do {
                        let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let data = try await Task.detached(priority: .userInitiated) {
                            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                            guard size <= 150 * 1024 * 1024 else { throw AppFailure("الحد الأقصى 150 MB") }
                            return try Data(contentsOf: url)
                        }.value
                        fileData = data; fileName = url.lastPathComponent
                    } catch { model.message = error.localizedDescription }
                }
            }
    }
}
struct ActivationView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        List {
            Section(model.t("بيانات الجهاز", "Device details")) {
                LabeledContent("MAC", value: model.identity?.mac ?? "—")
                LabeledContent("KEY", value: model.identity?.key ?? "—")
            }.textSelection(.enabled).font(.system(.body, design: .monospaced)).environment(\.layoutDirection, .leftToRight)
            Section {
                Text(model.status).foregroundColor(.cyan)
                if let license = model.profile.license {
                    if !license.lifetime {
                        let end = license.activated ? license.licenseEnd : license.trialEnd
                        if end > 0 { LabeledContent(model.t("الانتهاء", "Expires"), value: Date(timeIntervalSince1970: end).formatted(date: .abbreviated, time: .shortened)) }
                    }
                }
                if let time = model.lastSync { Text(model.t("آخر اتصال: ", "Last connected: ") + time.formatted(date: .omitted, time: .shortened)).font(.caption) }
                if !model.siteError.isEmpty { Text(model.siteError).foregroundColor(.orange).font(.caption) }
                Button(model.t("مزامنة الموقع", "Sync website")) { Task { await model.sync() } }.disabled(model.busy || model.demo)
                Link(model.t("فتح موقع التفعيل", "Open activation website"), destination: URL(string: "https://aadripro.com")!)
            }
            Text(model.t("هذا معرّف خاص بنسخة iOS وليس عنوان Wi-Fi. يُحفظ في Keychain مع تحديثات التطبيق. لا يمكن ضمان استعادته بعد مسح الجهاز أو حذف التطبيق.", "This is an iOS app identity, not the Wi-Fi MAC. It is kept in Keychain during app updates. Recovery after erasing the device or uninstalling is not guaranteed.")).font(.caption).foregroundColor(muted)
        }.navigationTitle(model.t("تفاصيل الحساب", "Account details"))
    }
}
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Section(model.t("المظهر والمشغل", "Appearance and player")) {
                Picker(model.t("اللغة", "Language"), selection: $model.profile.language) { Text("العربية").tag("ar"); Text("English").tag("en") }
                Picker(model.t("وضع ملء الشاشة", "Full-screen video"), selection: $model.profile.fit) {
                    Text(model.t("ملء الشاشة بالكامل", "Stretch to fill")).tag("fill")
                    Text(model.t("الحفاظ على الأبعاد", "Fit original ratio")).tag("fit")
                    Text(model.t("ملء مع قص الأطراف", "Crop to fill")).tag("crop")
                }
                Text(model.t("الوضع الافتراضي يغطي الشاشة بالكامل وقد يمدّد الصورة. وضع الحفاظ على الأبعاد قد يُظهر حواف سوداء.", "The default fills the whole screen and may stretch the picture. Fit preserves the ratio and may leave black bars.")).font(.caption).foregroundColor(muted)
            }
            Section(model.t("المزامنة والخصوصية", "Sync and privacy")) {
                Toggle(model.t("إظهار الاشتراكات المحلية في حساب الموقع", "Show local playlists on website"), isOn: $model.profile.shareCatalog)
                Text(model.t("اختياري: يرسل أسماء الاشتراكات وروابطها وأسماء المستخدمين إلى موقعك. قد يتضمن رابط M3U بيانات الدخول. عند إيقافه تتوقف المشاركات الجديدة؛ حذف البيانات السابقة يتم من الموقع.", "Optional: sends playlist names, URLs and usernames to your website. M3U URLs may contain credentials. Turning it off stops future sharing; previously shared data must be removed on the website.")).font(.caption).foregroundColor(muted)
            }
            Section {
                Text(model.t("المفضلة: افتح قسم القنوات أو الأفلام واضغط النجمة. اضغط مطولًا على العنصر لإضافته.", "Favorites: open Live TV or Movies and tap the star filter. Long-press an item to add it.")).font(.caption)
                Text("AADRI PRO · iOS 0.1.0")
            }
        }.navigationTitle(model.t("الإعدادات", "Settings")).disabled(model.busy)
            .onChange(of: model.profile.language) { _ in Task { await model.persist() } }
            .onChange(of: model.profile.fit) { _ in Task { await model.persist() } }
            .onChange(of: model.profile.shareCatalog) { _ in Task { await model.persist() } }
    }
}
private struct AppErrors: ViewModifier {
    @EnvironmentObject var model: AppModel
    func body(content: Content) -> some View {
        content.alert(model.t("تنبيه", "Notice"), isPresented: Binding(get: { !model.message.isEmpty }, set: { if !$0 { model.message = "" } })) {
            Button(model.t("حسنًا", "OK")) { model.message = "" }
        } message: { Text(model.message) }
    }
}
extension View { func appErrors() -> some View { modifier(AppErrors()) } }
