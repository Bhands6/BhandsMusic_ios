import Foundation

/// 歌单的远程曲库。
///
/// 本地只有 8 首，撑不起「每日推荐 30 首」这种标题 —— 之前是拿假数字糊过去的。
/// 现在启动时按关键词从网易云拉真实的 30 首填进来；拉不到就退回本地选曲，
/// 数字跟着真实内容走，不再撒谎。
@Observable
final class PlaylistStore {

    /// playlist.id → 远程曲目
    private(set) var tracks: [UUID: [Song]] = [:]
    private(set) var isRefreshing = false
    private(set) var lastError: String?

    /// 只尝试一次，别每次进页面都重打一轮
    @ObservationIgnored private var attempted = false

    /// 界面取曲目**统一走这里** —— 远程有就用远程，没有就用本地
    func songs(for playlist: Playlist) -> [Song] {
        tracks[playlist.id] ?? playlist.localSongs
    }

    /// 这个歌单现在是不是真的来自网易云
    func isRemote(_ playlist: Playlist) -> Bool {
        tracks[playlist.id] != nil
    }

    func loadAll() async {
        guard !attempted else { return }
        attempted = true
        isRefreshing = true
        defer { isRefreshing = false }

        var loaded: [UUID: [Song]] = [:]

        // 六个歌单并发拉，别串行等六轮
        await withTaskGroup(of: (UUID, [Song]?).self) { group in
            for playlist in MusicLibrary.playlists {
                group.addTask { (playlist.id, await Self.fetch(for: playlist)) }
            }
            for await (id, songs) in group {
                if let songs, !songs.isEmpty { loaded[id] = songs }
            }
        }

        tracks = loaded
        lastError = loaded.isEmpty ? "网易云接口不可用，已退回本地曲库" : nil
    }

    /// 重新拉一遍。登录/登出后要调 —— 「每日推荐」会跟着账号变。
    func reload() async {
        attempted = false
        tracks = [:]
        await loadAll()
    }

    private static func fetch(for playlist: Playlist) async -> [Song]? {
        do {
            // 「每日推荐」搜关键词是搜不出"推荐"的，走专门接口。
            // 登录了就用账号级的 /recommend/songs，没登录退回新歌速递。
            if playlist.title == "每日推荐" {
                if NeteaseSession.shared.isLoggedIn,
                   var daily = try? await NeteaseAPI.recommendSongs(),
                   !daily.isEmpty {
                    if let covers = try? await NeteaseAPI.covers(ids: daily.map(\.id)) {
                        for index in daily.indices {
                            daily[index].cover = covers[daily[index].id]
                        }
                    }
                    return daily.map(\.song)
                }
                return try await NeteaseAPI.newsong(limit: 30).map(\.song)
            }

            guard let keyword = playlist.remoteKeyword else { return nil }
            var found = try await NeteaseAPI.search(keyword, limit: 30)
            guard !found.isEmpty else { return nil }

            // `/search` 不给封面地址，补一次 `/song/detail`（批量，不是逐条）
            if let covers = try? await NeteaseAPI.covers(ids: found.map(\.id)) {
                for index in found.indices {
                    found[index].cover = covers[found[index].id]
                }
            }
            return found.map(\.song)
        } catch {
            return nil
        }
    }
}
