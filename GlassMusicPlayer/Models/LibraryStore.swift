import Foundation

/// 音乐库。
///
/// 启动时先用打包音轨顶上（保证离线可用），随后按下面这份清单
/// 从网易云解析出真实曲目替换掉。
///
/// **为什么不是下载音频打包进 App**：这些是版权歌曲，随 App 分发属于侵权，
/// 而且 12 首无损就几十 MB。走流式播放既合规，也不占体积。
///
/// 清单里只写「歌名 + 艺人」，运行时用 `/search` 解析成真实曲目 ——
/// 这样换歌只要改这里的字符串，不用重新找音频文件。
@Observable
final class LibraryStore {

    /// 想放进音乐库的歌。顺序即展示顺序。
    private static let catalog: [(title: String, artist: String)] = [
        ("山楂树之恋", "程佳佳"),
        ("带你一起去流浪", "海生"),
        ("爱要坦荡荡", "丁丁"),
        ("向云端", "海洋Bo"),
        ("不灵不灵", "很美味"),
        ("浪漫主义", "姜云升"),
        ("平凡日子里的挣扎", "曾抖抖"),
        ("已经有我啦", "姚小蝶"),
        ("如果再遇到爱的人", "刘宏宇Honey L"),
        ("董小姐", ""),
        ("山高路远", "烟火客"),
        ("河南浪漫宣言", "Qiaole巧乐"),
    ]

    /// 当前音乐库。初始是打包音轨，解析成功后整体替换。
    private(set) var songs: [Song] = MusicLibrary.songs
    private(set) var isLoading = false
    /// 是否已用上远程曲库
    private(set) var isRemote = false
    private(set) var lastError: String?

    @ObservationIgnored private var attempted = false

    /// 按专辑去重 —— 同一张专辑有多首歌时不该出现多行
    var albums: [Album] {
        var seen = Set<String>()
        return songs.compactMap { song in
            guard seen.insert("\(song.album)|\(song.artist)").inserted else { return nil }
            return Album(
                title: song.album,
                artist: song.artist,
                year: song.year,
                artworkName: song.artworkName,
                songIDs: [song.id]
            )
        }
    }

    /// 按艺人去重 —— 同一位歌手有两首歌时不该出现两行
    var artists: [Artist] {
        var seen = Set<String>()
        return songs.compactMap { song in
            guard seen.insert(song.artist).inserted else { return nil }
            return Artist(
                name: song.artist,
                genre: "精选",
                artworkName: song.artworkName,
                monthlyListeners: max(120_000, song.plays / 6)
            )
        }
    }

    /// 最近播放。真实产品该读本地历史，这里先取曲库前 6 首。
    var recentlyPlayed: [Song] { Array(songs.prefix(6)) }

    /// 新发行
    var newReleases: [Album] { Array(albums.sorted { $0.year > $1.year }.prefix(6)) }

    /// 热门单曲。远程曲目没有播放量，顺序就是曲库顺序。
    var topSongs: [Song] { songs }

    func load() async {
        guard !attempted else { return }
        attempted = true

        // 有缓存且清单没变就直接用 —— 清单是固定的，没必要每次启动都重新搜一遍。
        // 网易对高频请求会返回「操作频繁」，12 次搜索每次都打很容易触发。
        if let cached = Self.loadCache() {
            songs = cached
            isRemote = true
            return
        }

        isLoading = true
        defer { isLoading = false }

        // 12 个搜索不能一次全打出去 —— 实测并发 12 时上游会返回 502，
        // 解析失败条数一多就退回打包音轨了。分 4 条一批，稳得多。
        var resolved: [(Int, Song)] = []
        let batchSize = 4
        var start = 0

        while start < Self.catalog.count {
            let end = min(start + batchSize, Self.catalog.count)
            let batch = Array(Self.catalog[start..<end])
            let base = start

            await withTaskGroup(of: (Int, Song?).self) { group in
                for (offset, item) in batch.enumerated() {
                    group.addTask { (base + offset, await Self.resolve(item)) }
                }
                for await (index, song) in group {
                    if let song { resolved.append((index, song)) }
                }
            }
            start = end
        }

        // 一半以上解析成功就替换；否则宁可继续用打包音轨
        guard resolved.count >= Self.catalog.count / 2 else {
            lastError = "曲库解析失败（\(resolved.count)/\(Self.catalog.count)），先用打包音轨"
            return
        }

        var ordered = resolved.sorted { $0.0 < $1.0 }.map(\.1)

        // `/search` 不给封面地址，批量补一次
        if let covers = try? await NeteaseAPI.covers(ids: ordered.compactMap(\.neteaseID)) {
            for index in ordered.indices {
                guard let id = ordered[index].neteaseID, let cover = covers[id] else { continue }
                ordered[index].artworkName = cover.absoluteString
            }
        }

        songs = ordered
        isRemote = true
        lastError = nil
        Self.saveCache(ordered)
    }

    // MARK: - 缓存

    /// 缓存条目。只存重建 `Song` 需要的字段，不存整个 `Song`（它不 Codable）。
    private struct CacheEntry: Codable {
        let id: Int
        let title: String
        let artist: String
        let album: String
        let duration: Double
        let cover: String?
    }

    private static var cacheKey: String { "libraryCache" }

    /// 清单指纹。改了清单就得重新解析，否则还是旧的 12 首。
    private static var signature: String {
        catalog.map(\.title).joined(separator: "|")
    }

    private static func loadCache() -> [Song]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey + ".data"),
              UserDefaults.standard.string(forKey: cacheKey + ".sig") == signature,
              let entries = try? JSONDecoder().decode([CacheEntry].self, from: data),
              entries.count >= catalog.count / 2
        else { return nil }

        return entries.map { entry in
            Song(
                title: entry.title,
                artist: entry.artist,
                album: entry.album,
                duration: entry.duration,
                year: Calendar.current.component(.year, from: Date()),
                plays: 0,
                artworkName: entry.cover ?? "netease_\(entry.id)",
                lyrics: [],
                source: .netease(id: entry.id)
            )
        }
    }

    private static func saveCache(_ songs: [Song]) {
        let entries: [CacheEntry] = songs.compactMap { song in
            guard case .netease(let id) = song.source else { return nil }
            return CacheEntry(
                id: id,
                title: song.title,
                artist: song.artist,
                album: song.album,
                duration: song.duration,
                cover: song.artworkName.hasPrefix("http") ? song.artworkName : nil
            )
        }
        guard !entries.isEmpty, let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey + ".data")
        UserDefaults.standard.set(signature, forKey: cacheKey + ".sig")
    }

    /// 按「歌名 + 艺人」搜一首，要求标题对得上 —— 否则可能拿到翻唱或同名的别的歌。
    ///
    /// 最多试 3 次，间隔 2s / 5s。网易对高频请求会返回「操作频繁」，
    /// 立刻重试只会继续撞墙，必须给它退避的时间。
    private static func resolve(_ item: (title: String, artist: String)) async -> Song? {
        let keyword = item.artist.isEmpty ? item.title : "\(item.title) \(item.artist)"
        let normalized = item.title.replacingOccurrences(of: " ", with: "")
        let delays: [Double] = [0, 2, 5]

        for delay in delays {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard let tracks = try? await NeteaseAPI.search(keyword, limit: 5), !tracks.isEmpty else {
                continue
            }
            let match = tracks.first {
                $0.title.replacingOccurrences(of: " ", with: "").contains(normalized)
            } ?? tracks.first
            return match?.song
        }
        return nil
    }
}

private extension Song {
    /// 远程曲目才有网易云 id，本地打包音轨没有
    var neteaseID: Int? {
        if case .netease(let id) = source { return id }
        return nil
    }
}
