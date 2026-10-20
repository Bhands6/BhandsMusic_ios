import SwiftUI

/// 一个网络电台。
///
/// 和普通曲目最大的区别：**直播流没有时长、不能拖进度**。
/// 所以 `duration` 记为 0，`Song.isLive` 据此判断，界面换成「直播中」而不是进度条。
struct RadioStation: Identifiable, Hashable {
    let id: String
    let name: String
    /// 使用场景（学习 / 阅读 / 助眠…）
    let scene: String
    /// 风格标签，如「Lofi · Chill」
    let style: String
    let url: URL
    let hex: UInt32

    var color: Color { Color(hex: hex) }

    /// 直接吃字符串形式的地址，省得列表里每条都写 `URL(string:)!`。
    /// 地址都是写死的合法字面量 —— 解析失败说明数据写错了，这里崩掉比静默降级更好排查。
    init(id: String, name: String, scene: String, style: String, url: String, hex: UInt32) {
        self.id = id
        self.name = name
        self.scene = scene
        self.style = style
        self.url = URL(string: url)!
        self.hex = hex
    }

    /// 转成可播放的曲目。电台没有专辑和歌词，`lyrics` 留空即显示「纯音乐」。
    ///
    /// ⚠️ 不要直接调这个 —— 每次调用都会生成新的 `Song.id`，
    /// 队列里就找不到它了。对外一律用 `RadioCatalog.song(for:)` 取缓存实例。
    func makeSong() -> Song {
        Song(
            title: name,
            artist: style,
            album: "网络电台",
            duration: 0,
            year: 2026,
            plays: 0,
            artworkName: "radio_\(id)",
            lyrics: [],
            source: .stream(url)
        )
    }
}

enum RadioCatalog {

    /// 取自 [88lin/lofi-radio-web](https://github.com/88lin/lofi-radio-web)（MIT）的公开电台列表。
    ///
    /// 只保留能直连的 mp3 流，并逐个实测过连通性：
    /// 原列表里的 bilibili 直播间需要额外解析（AVPlayer 播不了），已剔除；
    /// Chill Sky / Groove Salad / Drone Zone / Swiss Classic / Jazz Groove 在本机连不上，也剔除了。
    ///
    /// 这些是面向公众开放的网络电台，收听不需要授权。
    static let stations: [RadioStation] = [
        .init(id: "lofi-box", name: "Lofi Box", scene: "学习", style: "Lofi · Chill", url: "https://boxradio-edge-00.streamafrica.net/lofi", hex: 0xA78BFA),
        .init(id: "lofi-cafe-studying", name: "Lofi Studying", scene: "学习", style: "Lofi · Study", url: "https://radio.loficafe.net/listen/studying/radio.mp3", hex: 0x3B82F6),
        .init(id: "lofi-cafe-japanese", name: "Lofi Japanese", scene: "阅读", style: "Japanese · Lofi", url: "https://radio.loficafe.net/listen/japanese-lofi/radio.mp3", hex: 0xF472B6),
        .init(id: "jazz-box", name: "Jazz Box", scene: "阅读", style: "Jazz · Smooth", url: "https://boxradio-edge-01.streamafrica.net/jazz", hex: 0xD946EF),
        .init(id: "b3cks-radio", name: "B3cks Radio", scene: "阅读", style: "Lofi · Relax", url: "https://radio.b3ck.com/listen/b3cks-radio/radio.mp3", hex: 0xFF7096),
        .init(id: "chill-wave", name: "Chill Wave", scene: "放松", style: "Chill · Electro", url: "https://boxradio-edge-00.streamafrica.net/chillwave", hex: 0xEC4899),
        .init(id: "lofi-cafe-chilling", name: "Lofi Chilling", scene: "放松", style: "Lofi · Chill", url: "https://radio.loficafe.net/listen/chilling/radio.mp3", hex: 0xF65C71),
        .init(id: "paradise", name: "Paradise", scene: "放松", style: "Chill · Alt", url: "https://stream.radioparadise.com/mellow-128", hex: 0xF59E0B),
        .init(id: "freecodecamp-coderadio", name: "Code Radio", scene: "编程", style: "Lofi · Coding", url: "https://coderadio-admin-v2.freecodecamp.org/listen/coderadio/radio.mp3", hex: 0x9050B3),
        .init(id: "rain-sounds", name: "Rain Sounds", scene: "助眠", style: "Ambient · Nature", url: "https://boxradio-edge-01.streamafrica.net/rain", hex: 0x0EA5E9),
        .init(id: "lofi-cafe-sleeping", name: "Lofi Sleeping", scene: "助眠", style: "Lofi · Sleep", url: "https://radio.loficafe.net/listen/sleeping/radio.mp3", hex: 0x498EEF),
        .init(id: "asp", name: "ASP", scene: "助眠", style: "Ambient · Sleep", url: "https://radio.stereoscenic.com/asp-s", hex: 0x6366F1),
        .init(id: "jazz-smooth", name: "Jazz Smooth", scene: "办公", style: "Jazz · Mellow", url: "https://smoothjazz.cdnstream1.com/2585_128.mp3", hex: 0xA855F7),
        .init(id: "rap", name: "Rap Beats", scene: "运动", style: "Hip-Hop · Beats", url: "https://boxradio-edge-00.streamafrica.net/rap", hex: 0xF43F5E),
        .init(id: "lofi-cafe-gaming", name: "Lofi Gaming", scene: "娱乐", style: "Lofi · Gaming", url: "https://radio.loficafe.net/listen/gaming/radio.mp3", hex: 0x22C55E)
    ]

    /// 电台对应的曲目队列 —— 点任意一台就按整个列表播，切歌即换台。
    /// 缓存成 `static let`，保证 `Song.id` 稳定，`play(_:in:)` 才能在队列里定位。
    static let songs: [Song] = stations.map { $0.makeSong() }

    /// 取某台对应的曲目实例（来自上面的缓存，不是新建）
    static func song(for station: RadioStation) -> Song {
        guard let index = stations.firstIndex(of: station), index < songs.count else {
            return songs[0]
        }
        return songs[index]
    }
}
