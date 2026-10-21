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

    var albums: [Album] {
        songs.map { song in
            Album(
                title: song.album,
                artist: song.artist,
                year: song.year,
                artworkName: song.artworkName,
                songIDs: [song.id]
            )
        }
    }

    var artists: [Artist] {
        songs.map { song in
            Artist(
                name: song.artist,
                genre: "精选",
                artworkName: song.artworkName,
                monthlyListeners: max(120_000, song.plays / 6)
            )
        }
    }

    func load() async {
        guard !attempted else { return }
        attempted = true
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
    }

    /// 按「歌名 + 艺人」搜一首，要求标题对得上 —— 否则可能拿到翻唱或同名的别的歌。
    /// 失败重试一次：上游偶发 502，重试一次基本能成。
    private static func resolve(_ item: (title: String, artist: String)) async -> Song? {
        let keyword = item.artist.isEmpty ? item.title : "\(item.title) \(item.artist)"
        let normalized = item.title.replacingOccurrences(of: " ", with: "")

        for _ in 0..<2 {
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
