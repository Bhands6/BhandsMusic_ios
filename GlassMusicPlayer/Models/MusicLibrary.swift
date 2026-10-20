import SwiftUI
import Observation

// MARK: - 歌词

struct LyricLine: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let time: TimeInterval
}

// MARK: - 歌曲

/// 音轨来源。
enum SongSource: Hashable {
    /// 打包进 App 的 m4a
    case bundled
    /// 网络流（电台 / 远程直链）。直播流没有时长。
    case stream(URL)
    /// 网易云曲目。播放地址在真正播放时才解析 ——
    /// 搜索结果一次 20 条，提前全取就是 20 个请求。
    case netease(id: Int)
}

struct Song: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let year: Int
    let plays: Int
    let artworkName: String
    /// 纯音乐留空，界面会显示「纯音乐 · 暂无歌词」
    let lyrics: [LyricLine]
    /// 默认是打包音轨，电台等远程源显式传入
    var source: SongSource = .bundled

    /// 直播流：没有时长、不能拖进度
    var isLive: Bool { duration <= 0 }

    var durationText: String { isLive ? "直播" : Song.timeText(duration) }

    /// 音频资源名：和封面同名（`cover_ink_rivers` → `ink_rivers`）
    var audioName: String { artworkName.replacingOccurrences(of: "cover_", with: "") }

    /// 打包进 App 的音轨。
    /// 同步文件夹可能把资源摊平到 bundle 根，也可能保留 `Audio/` 子目录，两种都试一下。
    var audioURL: URL? {
        switch source {
        case .stream(let url):
            return url
        case .netease:
            // 地址是异步解析的，这里没有
            return nil
        case .bundled:
            return Bundle.main.url(forResource: audioName, withExtension: "m4a")
                ?? Bundle.main.url(forResource: audioName, withExtension: "m4a", subdirectory: "Audio")
        }
    }

    var playsText: String {
        plays >= 10_000
            ? String(format: "%.0f 万次播放", Double(plays) / 10_000)
            : "\(plays) 次播放"
    }

    var isInstrumental: Bool { lyrics.isEmpty }

    static func timeText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - 专辑

struct Album: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let artist: String
    let year: Int
    let artworkName: String
    let songIDs: [UUID]
}

// MARK: - 歌单

struct Playlist: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
    let colors: [Color]
    let songIDs: [UUID]

    /// 曲目数**由 `songIDs` 推导**，不再单独写死。
    ///
    /// 之前是独立字段，写的是 30 / 60 / 100…，但 `songIDs` 只放了整库 8 首 ——
    /// 于是出现「30 首 · 31 分钟」这种自相矛盾的显示。
    var count: Int { songIDs.count }
}

// MARK: - 艺人

struct Artist: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let genre: String
    let artworkName: String
    let monthlyListeners: Int

    var listenersText: String {
        String(format: "%.0f 万月听众", Double(monthlyListeners) / 10_000)
    }
}

// MARK: - 曲库

enum MusicLibrary {

    // MARK: 歌曲

    static let songs: [Song] = [
        Song(
            title: "Neon Tokyo",
            artist: "AURORA DRIFT",
            album: "Afterglow",
            duration: 225,
            year: 2024,
            plays: 12_480_000,
            artworkName: "cover_neon_tokyo",
            lyrics: [
                LyricLine(text: "霓虹在雨里碎成粒子", time: 0),
                LyricLine(text: "Neon rain is falling down", time: 30),
                LyricLine(text: "频率穿过整座城市", time: 62),
                LyricLine(text: "Every signal finds a home", time: 94),
                LyricLine(text: "把心跳调到 128 BPM", time: 128),
                LyricLine(text: "Tokyo lights will lead me on", time: 162),
                LyricLine(text: "而夜色还很长", time: 196)
            ]
        ),
        Song(
            title: "Cyber Bloom",
            artist: "KIRA & 电子羊",
            album: "Neon Bloom",
            duration: 252,
            year: 2025,
            plays: 8_930_000,
            artworkName: "cover_cyber_bloom",
            lyrics: [
                LyricLine(text: "在数据的缝隙里开花", time: 0),
                LyricLine(text: "Blue light on my skin", time: 34),
                LyricLine(text: "你说这是最后一次", time: 72),
                LyricLine(text: "Bloom again, bloom again", time: 110),
                LyricLine(text: "所有的 0 都变成 1", time: 150),
                LyricLine(text: "然后我们重新开始", time: 196)
            ]
        ),
        Song(
            title: "午夜霓虹",
            artist: "赛博乐队 NEON-9",
            album: "午夜霓虹",
            duration: 208,
            year: 2023,
            plays: 21_760_000,
            artworkName: "cover_midnight_neon",
            lyrics: [
                LyricLine(text: "十二点的街灯忽然亮了", time: 0),
                LyricLine(text: "招牌在风里晃成一片海", time: 28),
                LyricLine(text: "我数着口袋里剩下的硬币", time: 58),
                LyricLine(text: "够买一杯热的关东煮", time: 88),
                LyricLine(text: "午夜霓虹 别为我熄灭", time: 122),
                LyricLine(text: "再走一段 就到家了", time: 160)
            ]
        ),
        Song(
            title: "Deep Space Love",
            artist: "NOVA",
            album: "Deep Space",
            duration: 302,
            year: 2024,
            plays: 5_240_000,
            artworkName: "cover_deep_space_love",
            lyrics: []
        ),
        Song(
            title: "Velvet Circuit",
            artist: "SYNTHWAVE 88",
            album: "Velvet Circuit",
            duration: 234,
            year: 2025,
            plays: 3_610_000,
            artworkName: "cover_velvet_circuit",
            lyrics: []
        ),
        Song(
            title: "水墨江湖",
            artist: "林间",
            album: "水墨江湖",
            duration: 276,
            year: 2022,
            plays: 34_180_000,
            artworkName: "cover_ink_rivers",
            lyrics: [
                LyricLine(text: "提笔是山 落笔是水", time: 0),
                LyricLine(text: "一叶舟横过旧时的渡口", time: 36),
                LyricLine(text: "谁在楼上弹一曲琵琶", time: 78),
                LyricLine(text: "弹断了半生的江湖", time: 118),
                LyricLine(text: "风起时 我还在路上", time: 160),
                LyricLine(text: "风停时 已是他乡", time: 208)
            ]
        ),
        Song(
            title: "Tokyo Rain",
            artist: "FM 120",
            album: "Tokyo Rain",
            duration: 168,
            year: 2023,
            plays: 9_750_000,
            artworkName: "cover_tokyo_rain",
            lyrics: []
        ),
        Song(
            title: "Chrome Heart",
            artist: "电子心脏",
            album: "Chrome Heart",
            duration: 245,
            year: 2024,
            plays: 6_420_000,
            artworkName: "cover_chrome_heart",
            lyrics: []
        )
    ]

    static func song(titled title: String) -> Song {
        songs.first { $0.title == title } ?? songs[0]
    }

    // MARK: 专辑

    static let albums: [Album] = songs.map { song in
        Album(
            title: song.album,
            artist: song.artist,
            year: song.year,
            artworkName: song.artworkName,
            songIDs: [song.id]
        )
    }

    // MARK: 歌单

    /// 确定性洗牌：同一天内结果固定，隔天换一批。
    ///
    /// 用线性同余生成器而不是 `shuffle()` —— 后者每次启动都不同，
    /// 「每天 6:00 更新」的语义就变成「每次打开都变」了。
    /// `salt` 用来让不同歌单取到不同的排列。
    static func dailyPick(_ count: Int, salt: UInt64) -> [UUID] {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        var seed = UInt64(day) &* 7919 &+ salt &* 104_729 &+ 12_345

        var pool = songs
        var picked: [Song] = []
        while picked.count < min(count, songs.count), !pool.isEmpty {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let index = Int(seed >> 33) % pool.count
            picked.append(pool.remove(at: index))
        }
        return picked.map(\.id)
    }

    static let playlists: [Playlist] = [
        Playlist(
            title: "每日推荐",
            subtitle: "每天 6:00 更新",
            symbol: "calendar",
            colors: [Color(hex: 0xFFB347), Color(hex: 0xFF6B6B)],
            songIDs: dailyPick(6, salt: 0)
        ),
        Playlist(
            title: "民谣",
            subtitle: "吉他与人声",
            symbol: "guitars.fill",
            colors: [Color(hex: 0x7A9A3F), Color(hex: 0xD4C685)],
            songIDs: dailyPick(4, salt: 1)
        ),
        Playlist(
            title: "抖音热曲",
            subtitle: "全网热播",
            symbol: "flame.fill",
            // 红 → 青在 RGB 里直接插值会经过灰色，中段糊成脏粉。
            // 中间插一个饱和紫，路径才一直在高饱和区。
            colors: [Color(hex: 0xFE2C55), Color(hex: 0xA82AC7), Color(hex: 0x25F4EE)],
            songIDs: dailyPick(5, salt: 2)
        ),
        Playlist(
            title: "飙升榜",
            subtitle: "热度上升最快",
            symbol: "chart.line.uptrend.xyaxis",
            colors: [Color(hex: 0x7B2FF7), Color(hex: 0xE10098)],
            // 榜单按真实播放量排，不做随机
            songIDs: songs.sorted { $0.plays > $1.plays }.map(\.id)
        ),
        Playlist(
            title: "华语新声",
            subtitle: "编辑部精选",
            symbol: "sparkles",
            colors: [Color(hex: 0xD63031), Color(hex: 0xFDCB6E)],
            songIDs: dailyPick(4, salt: 3)
        ),
        Playlist(
            title: "电子浪潮",
            subtitle: "从地下俱乐部到主舞台",
            symbol: "waveform",
            colors: [Color(hex: 0x6C5CE7), Color(hex: 0x00CEC9)],
            songIDs: dailyPick(5, salt: 4)
        )
    ]

    // MARK: 艺人

    static let artists: [Artist] = songs.map { song in
        Artist(
            name: song.artist,
            genre: genre(for: song),
            artworkName: song.artworkName,
            monthlyListeners: max(120_000, song.plays / 6)
        )
    }

    private static func genre(for song: Song) -> String {
        switch song.title {
        case "Neon Tokyo", "Cyber Bloom":  return "合成器浪潮"
        case "午夜霓虹", "Chrome Heart":     return "电子"
        case "Deep Space Love":            return "氛围电子"
        case "Velvet Circuit", "Tokyo Rain": return "Lo-Fi"
        default:                           return "国风电音"
        }
    }

    // MARK: 首页分组

    /// 最近播放（按「上次听到的位置」排，真实产品里来自本地历史）
    static let recentlyPlayed: [Song] = [
        songs[2], songs[0], songs[5], songs[3], songs[7], songs[1]
    ]

    /// 为你推荐 —— 首页用三列网格，正好 6 个铺满两行
    static let madeForYou: [Playlist] = playlists

    /// 新发行
    static let newReleases: [Album] = Array(albums.sorted { $0.year > $1.year }.prefix(6))

    /// 热门单曲
    static let topSongs: [Song] = songs.sorted { $0.plays > $1.plays }
}

// MARK: - 播放状态

enum RepeatMode {
    case off, all, one

    var symbol: String {
        switch self {
        case .off, .all: return "repeat"
        case .one:       return "repeat.1"
        }
    }

    var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

@Observable
final class PlayerModel {
    var queue: [Song] = MusicLibrary.songs
    var currentIndex: Int = 0
    var isPlaying: Bool = false
    var progress: Double = 0
    var isShuffleOn: Bool = false
    var repeatMode: RepeatMode = .off
    /// 正在播放页的歌词模式
    var showsLyrics: Bool = false
    /// 用户正在拖进度条 —— 期间不让播放器的进度回调覆盖手指位置
    var isSeeking: Bool = false
    private(set) var likedIDs: Set<UUID> = []

    /// 随机播放走过的曲目下标，「上一曲」按这个回退
    @ObservationIgnored private var history: [Int] = []

    /// 真正的音频引擎。`@ObservationIgnored`：它不是 UI 状态，不需要被观察。
    @ObservationIgnored private let engine = AudioEngine()

    init() {
        engine.onProgress = { [weak self] value in
            // 直播流没有进度可言，也不让拖拽被覆盖
            guard let self, !self.isSeeking, !self.current.isLive else { return }
            self.progress = value
        }
        engine.onFinish = { [weak self] in
            self?.handleTrackFinished()
        }
        engine.onRemoteToggle = { [weak self] in
            self?.togglePlayPause()
        }
        engine.onRemoteNext = { [weak self] in
            self?.next()
        }
        engine.onRemotePrevious = { [weak self] in
            _ = self?.previous()
        }

        // 启动时只装载不自动播 —— 一打开 App 就出声太粗暴。
        // 自动化截图时用 -autoplay 1 强制出声，验证音频链路。
        loadCurrent(autoplay: DebugLaunch.autoplays)

        // -radio N 直接进某个网络电台，验证直播流
        if DebugLaunch.radioIndex > 0 {
            let index = min(DebugLaunch.radioIndex - 1, RadioCatalog.stations.count - 1)
            play(RadioCatalog.song(for: RadioCatalog.stations[index]), in: RadioCatalog.songs)
        }
    }

    var current: Song {
        guard !queue.isEmpty else { return MusicLibrary.songs[0] }
        return queue[min(max(currentIndex, 0), queue.count - 1)]
    }

    var elapsed: Double { progress * current.duration }

    var remaining: Double { (1 - progress) * current.duration }

    /// 队列里当前曲目之后的 5 首
    var upNext: [Song] {
        guard queue.count > 1 else { return [] }
        return (1...min(5, queue.count - 1)).map { offset in
            queue[(currentIndex + offset) % queue.count]
        }
    }

    func isLiked(_ song: Song) -> Bool { likedIDs.contains(song.id) }

    func toggleLike(_ song: Song) {
        if likedIDs.contains(song.id) {
            likedIDs.remove(song.id)
        } else {
            likedIDs.insert(song.id)
        }
    }

    /// 从某个列表点播一首歌 —— 队列会被替换成这个列表
    func play(_ song: Song, in list: [Song]? = nil) {
        // 换队列了，随机历史作废
        history.removeAll()

        if let list, !list.isEmpty {
            queue = list
            currentIndex = list.firstIndex(of: song) ?? 0
        } else if let index = queue.firstIndex(of: song) {
            currentIndex = index
        } else {
            queue = [song]
            currentIndex = 0
        }
        loadCurrent(autoplay: true)
    }

    func next() {
        guard !queue.isEmpty else { return }

        if isShuffleOn {
            history.append(currentIndex)
            // 只留最近 50 条，避免长时间播放把数组撑大
            if history.count > 50 { history.removeFirst() }
            currentIndex = randomIndex(excluding: currentIndex)
        } else {
            history.removeAll()
            currentIndex = (currentIndex + 1) % queue.count
        }
        loadCurrent(autoplay: true)
    }

    /// 随机但不重复当前这首。队列只有一首时原地不动。
    private func randomIndex(excluding index: Int) -> Int {
        guard queue.count > 1 else { return index }
        var candidate = index
        while candidate == index {
            candidate = Int.random(in: 0..<queue.count)
        }
        return candidate
    }

    /// - Returns: 是否真的切换/重播了。`false` 表示已经是第一首、什么也没发生 ——
    ///   调用方据此决定要不要弹提示。
    @discardableResult
    func previous() -> Bool {
        guard !queue.isEmpty else { return false }

        // 播到 3 秒以后，上一首先回到本曲开头 —— 和真实播放器一致
        if elapsed > 3 {
            seek(to: 0)
            return true
        }

        // 随机模式下按历史回退，而不是按队列序号
        if isShuffleOn, let previousIndex = history.popLast() {
            currentIndex = previousIndex
            loadCurrent(autoplay: true)
            return true
        }

        // 已经是第一首：不再循环到末尾，交给调用方提示
        guard currentIndex > 0 else { return false }
        currentIndex -= 1
        loadCurrent(autoplay: true)
        return true
    }

    // MARK: - 播放控制

    func togglePlayPause() {
        isPlaying.toggle()
        if isPlaying {
            engine.play()
        } else {
            engine.pause()
        }
        syncNowPlaying()
    }

    func seek(to value: Double) {
        let clamped = min(max(value, 0), 1)
        progress = clamped
        engine.seek(to: clamped * current.duration)
        syncNowPlaying()
    }

    /// 装载当前曲目。`autoplay` 决定装载后是否立刻出声。
    private func loadCurrent(autoplay: Bool) {
        progress = 0
        isPlaying = autoplay

        // 网易云：先异步取播放地址，取到再装载
        if case .netease(let id) = current.source {
            let requested = current
            isPlaying = false

            Task { @MainActor in
                guard let url = try? await NeteaseAPI.streamURL(for: id) else { return }
                // 解析期间用户可能已经切歌了
                guard self.current.id == requested.id else { return }

                self.engine.load(url: url, duration: requested.duration, autoplay: autoplay)
                self.isPlaying = autoplay
                self.syncNowPlaying()
            }
            return
        }

        guard let url = current.audioURL else {
            // 找不到音轨时退化成"静音播放"，UI 仍然可操作
            isPlaying = false
            return
        }
        engine.load(url: url, duration: current.duration, autoplay: autoplay)
        syncNowPlaying()
    }

    /// 一曲自然播完。按循环模式决定重播 / 下一首 / 停下。
    private func handleTrackFinished() {
        switch repeatMode {
        case .one:
            seek(to: 0)
            engine.play()
            isPlaying = true
        case .all:
            next()
        case .off:
            if currentIndex < queue.count - 1 {
                next()
            } else {
                progress = 1
                isPlaying = false
            }
        }
    }

    private func syncNowPlaying() {
        engine.updateNowPlaying(
            title: current.title,
            artist: current.artist,
            artworkName: current.artworkName,
            elapsed: progress * current.duration,
            isPlaying: isPlaying
        )
    }
}

// MARK: - 颜色工具

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
