import SwiftUI
import AVFoundation
import AVKit

struct TrackChoice: Identifiable {
    let id: Int
    let name: String
    let option: AVMediaSelectionOption?
}
@MainActor final class Playback: ObservableObject {
    let player = AVPlayer()
    @Published var item: Media?
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var playing = false
    @Published var buffering = false
    @Published var failure = ""
    @Published var audio: [TrackChoice] = []
    @Published var subtitles: [TrackChoice] = []
    private var audioGroup: AVMediaSelectionGroup?
    private var subtitleGroup: AVMediaSelectionGroup?
    private var observer: Any?
    private var observation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var generation = UUID()
    private var resumeSeconds: Double = 0
    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.position = time.seconds.isFinite ? max(0, time.seconds) : 0
                let duration = self.player.currentItem?.duration.seconds ?? 0
                self.duration = duration.isFinite ? max(0, duration) : 0
            }
        }
        rateObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.playing = self.player.timeControlStatus == .playing
                self.buffering = self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }
        }
    }
    func open(_ item: Media, resume: Double = 0) {
        guard let url = URL(string: item.url) else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { failure = "تعذر تهيئة الصوت / Audio unavailable"; return }
        stop(); self.item = item; generation = UUID(); resumeSeconds = resume
        let token = generation
        let next = AVPlayerItem(url: url)
        observation = next.observe(\.status, options: [.initial, .new]) { [weak self] current, _ in
            let status = current.status
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if status == .failed { self.failure = "تعذر تشغيل البث. تحقق من الرابط وصيغة HLS أو MP4 / Stream unavailable or unsupported codec"; self.buffering = false }
                if status == .readyToPlay {
                    if self.resumeSeconds > 0 {
                        let end = self.player.currentItem?.duration.seconds ?? 0
                        if end.isFinite && self.resumeSeconds < end - 5 { self.seek(self.resumeSeconds) }
                        self.resumeSeconds = 0
                    }
                    await self.loadTracks(token: token)
                }
            }
        }
        player.replaceCurrentItem(with: next); player.play()
    }
    func stop() {
        generation = UUID(); player.pause(); observation = nil
        player.replaceCurrentItem(with: nil); item = nil; playing = false; buffering = false
        position = 0; duration = 0; failure = ""; audio = []; subtitles = []; audioGroup = nil; subtitleGroup = nil
    }
    func toggle() {
        if player.timeControlStatus == .paused { player.play() } else { player.pause() }
    }
    func seek(_ seconds: Double) { player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600)) }
    func loadTracks(token: UUID) async {
        guard let asset = player.currentItem?.asset else { return }
        let a = try? await asset.loadMediaSelectionGroup(for: .audible)
        let s = try? await asset.loadMediaSelectionGroup(for: .legible)
        guard generation == token else { return }
        audioGroup = a; subtitleGroup = s
        audio = (a?.options ?? []).enumerated().map { TrackChoice(id: $0.offset, name: $0.element.displayName, option: $0.element) }
        subtitles = [TrackChoice(id: -1, name: "إيقاف الترجمة / Off", option: nil)] + (s?.options ?? []).enumerated().map { TrackChoice(id: $0.offset, name: $0.element.displayName, option: $0.element) }
    }
    func select(_ choice: TrackChoice, subtitle: Bool) {
        guard let group = subtitle ? subtitleGroup : audioGroup else { return }
        player.currentItem?.select(choice.option, in: group)
    }
}
final class VideoLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var videoLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var fit = "fit"
    override var accessibilityValue: String? {
        get {
            let rect = convert(bounds, to: window)
            let screen = window?.bounds ?? .zero
            let metrics: [String: Any] = ["fit": fit, "x": rect.minX, "y": rect.minY,
                "width": bounds.width, "height": bounds.height,
                "windowWidth": screen.width, "windowHeight": screen.height]
            guard let data = try? JSONSerialization.data(withJSONObject: metrics) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set { }
    }
}
struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    let fit: String
    func makeUIView(context: Context) -> VideoLayerView {
        let view = VideoLayerView(); view.backgroundColor = .black
        view.isAccessibilityElement = true; view.accessibilityIdentifier = "videoSurface"
        view.accessibilityLabel = "Video"
        return view
    }
    func updateUIView(_ view: VideoLayerView, context: Context) {
        view.videoLayer.player = player
        view.videoLayer.videoGravity = fit == "fit" ? .resizeAspect : fit == "crop" ? .resizeAspectFill : .resize
        view.fit = fit
    }
    static func dismantleUIView(_ view: VideoLayerView, coordinator: ()) { view.videoLayer.player = nil }
}
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { let view = AVRoutePickerView(); view.tintColor = .white; return view }
    func updateUIView(_ view: AVRoutePickerView, context: Context) { }
}
struct Transport: View {
    @ObservedObject var playback: Playback
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 8) {
            if playback.duration > 0 && playback.item?.kind != .live {
                Slider(value: Binding(get: { min(playback.position, playback.duration) }, set: { playback.seek($0) }), in: 0...max(1, playback.duration))
                    .accessibilityLabel(model.t("موضع التشغيل", "Playback position"))
            }
            HStack(spacing: 24) {
                if playback.item?.kind != .live { Button { playback.seek(playback.position - 10) } label: { Image(systemName: "gobackward.10") } }
                Button { model.enforceLicense(); if model.demo || model.permitted { playback.toggle() } } label: { Image(systemName: playback.playing ? "pause.fill" : "play.fill") }
                    .accessibilityIdentifier("playPause").accessibilityLabel(model.t("تشغيل أو إيقاف مؤقت", "Play or pause"))
                if playback.item?.kind != .live { Button { playback.seek(playback.position + 10) } label: { Image(systemName: "goforward.10") } }
                Spacer(minLength: 0)
                Menu {
                    if !playback.audio.isEmpty {
                        Section(model.t("الصوت", "Audio")) { ForEach(playback.audio) { choice in Button(choice.name) { playback.select(choice, subtitle: false) } } }
                    }
                    Section(model.t("الترجمة المدمجة", "Embedded subtitles")) { ForEach(playback.subtitles) { choice in Button(choice.name) { playback.select(choice, subtitle: true) } } }
                } label: { Image(systemName: "captions.bubble") }.accessibilityLabel(model.t("الصوت والترجمة", "Audio and subtitles"))
                AirPlayButton().frame(width: 32, height: 32)
            }.font(.title3).buttonStyle(.plain)
        }.padding(12).foregroundColor(.white).tint(.cyan)
    }
}
struct PlayerPanel: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var playback: Playback
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Color.black
                if playback.item != nil && !model.fullscreen { VideoSurface(player: playback.player, fit: "fit") }
                if playback.item == nil { Label(model.t("اختر قناة لمعاينة البث", "Choose a stream"), systemImage: "play.tv").font(.caption).foregroundColor(.gray) }
                if playback.buffering { ProgressView().tint(.white) }
            }.aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10))
            if let item = playback.item {
                Text(item.name).font(.headline).lineLimit(2)
                if !playback.failure.isEmpty {
                    Text(playback.failure).font(.caption).foregroundColor(.orange)
                    Button(model.t("إعادة المحاولة", "Retry")) { Task { await model.play(item) } }
                }
                Transport(playback: playback)
                HStack {
                    Button { Task { await model.favorite(item) } } label: { Image(systemName: model.isFavorite(item) ? "star.fill" : "star") }.disabled(model.demo)
                    Spacer()
                    if item.kind == .live && model.account?.source.mode == "xtream" { Button("EPG") { Task { await model.showGuide() } } }
                    Button { model.fullscreen = true } label: { Label(model.t("ملء الشاشة", "Full screen"), systemImage: "arrow.up.left.and.arrow.down.right") }
                        .accessibilityIdentifier("expandChannel")
                }.buttonStyle(.bordered).tint(.cyan)
            }
        }
    }
}
struct FullscreenPlayer: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var playback: Playback
    @State private var controls = true
    @State private var timerID = UUID()
    @State private var landscape = true
    @State private var originalOrientation: UIInterfaceOrientation = .unknown
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoSurface(player: playback.player, fit: model.profile.fit)
                .ignoresSafeArea().contentShape(Rectangle()).onTapGesture { controls.toggle(); timerID = UUID() }
            if playback.buffering { ProgressView().tint(.white) }
            if !playback.failure.isEmpty { Text(playback.failure).padding().background(.black.opacity(0.7)).foregroundColor(.orange) }
            if controls {
                VStack {
                    HStack(spacing: 18) {
                        Button { model.fullscreen = false } label: { Image(systemName: "xmark") }.accessibilityIdentifier("exitFullscreen").accessibilityLabel(model.t("رجوع", "Back"))
                        Text(playback.item?.name ?? "").lineLimit(1).font(.headline)
                        Spacer()
                        Menu {
                            Button(model.t("ملء الشاشة بالكامل", "Stretch to fill")) { setFit("fill") }
                            Button(model.t("الحفاظ على الأبعاد", "Fit original ratio")) { setFit("fit") }
                            Button(model.t("ملء مع قص الأطراف", "Crop to fill")) { setFit("crop") }
                        } label: { Image(systemName: "aspectratio") }.accessibilityIdentifier("videoFit")
                        Button { landscape.toggle(); rotate() } label: { Image(systemName: "rotate.right") }.accessibilityLabel(model.t("تدوير الشاشة", "Rotate screen"))
                    }.padding().background(.black.opacity(0.65))
                    Spacer()
                    Transport(playback: playback).background(.black.opacity(0.65))
                }.padding(.horizontal, 8).foregroundColor(.white).buttonStyle(.plain)
            }
        }.background(Color.black).statusBarHidden(true).persistentSystemOverlays(.hidden)
            .task(id: timerID) {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if !Task.isCancelled { controls = false }
            }
            .onAppear {
                originalOrientation = activeScene?.interfaceOrientation ?? .unknown
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .task {
                // Request rotation after the full-screen presentation transition completes.
                try? await Task.sleep(nanoseconds: 700_000_000)
                if !Task.isCancelled { rotate() }
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
                if originalOrientation != .unknown { activeScene?.requestGeometryUpdate(.iOS(interfaceOrientations: originalOrientation.isLandscape ? .landscape : .portrait)) { _ in } }
            }
    }
    func setFit(_ fit: String) { model.profile.fit = fit; timerID = UUID(); Task { await model.persist() } }
    var activeScene: UIWindowScene? { UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive } }
    func rotate() {
        guard let scene = activeScene else { return }
        var controller = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        controller?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: landscape ? .landscapeRight : .portrait)) { error in
            print("Fullscreen rotation denied: \(error.localizedDescription)")
        }
    }
}
