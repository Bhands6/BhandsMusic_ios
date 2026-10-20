import Foundation

/// 网易云音乐 API 客户端。
///
/// 后端用的是社区维护的 [NeteaseCloudMusicApi Enhanced](https://github.com/88lin/api-enhanced)，
/// 需要自己起一份（`node app.js`，默认 3000 端口），再把 `baseURL` 指过去。
///
/// **为什么要自己部署**：原版 Binaryify 的仓库 2024 年停更，网易改了协议（xeapi），
/// 老版本拿不到播放地址。Enhanced 版跟进了新协议，但它是个 Node 服务，必须单独跑。
///
/// ⚠️ 非官方接口，仅供个人学习使用。曲库版权归网易云所有，
/// 用它的内容做上架应用会被审核拒绝，也不符合网易云的服务条款。
enum NeteaseAPI {

    /// 后端地址。默认指向本机 —— 模拟器可以直接访问 Mac 的 localhost。
    /// 部署到公网后改这里（或用 `-ncm <url>` 启动参数覆盖）。
    static var baseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "ncm"), let url = URL(string: override) {
            return url
        }
        return URL(string: "http://localhost:3456")!
    }

    /// 一条搜索结果。只保留界面用得到的字段。
    struct Track: Identifiable, Hashable {
        let id: Int
        let title: String
        let artist: String
        let album: String
        /// 秒
        let duration: Double

        var durationText: String { Song.timeText(duration) }
    }

    enum Failure: LocalizedError {
        case badResponse
        case noStream

        var errorDescription: String? {
            switch self {
            case .badResponse: return "接口返回异常"
            case .noStream: return "该曲目暂无可播放地址（版权或会员限制）"
            }
        }
    }

    // MARK: - 接口

    /// 搜索歌曲。
    static func search(_ keyword: String, limit: Int = 20) async throws -> [Track] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let json = try await get("/search", ["keywords": trimmed, "limit": String(limit), "type": "1"])
        guard
            let result = json["result"] as? [String: Any],
            let songs = result["songs"] as? [[String: Any]]
        else { throw Failure.badResponse }

        return songs.compactMap { item in
            guard let id = item["id"] as? Int, let name = item["name"] as? String else { return nil }

            // 艺人可能是数组（多艺人合作）
            let artists = (item["artists"] as? [[String: Any]])?
                .compactMap { $0["name"] as? String }
                .joined(separator: " / ") ?? "未知艺人"

            let album = (item["album"] as? [String: Any])?["name"] as? String ?? ""
            // 网易云给的是毫秒
            let ms = item["duration"] as? Double ?? Double(item["dt"] as? Int ?? 0)

            return Track(id: id, title: name, artist: artists, album: album, duration: ms / 1000)
        }
    }

    /// 取播放地址。
    ///
    /// 返回的常常是 `http://m7xx.music.126.net/...`，这里统一换成 https ——
    /// iOS 的 ATS 默认拦明文 HTTP，换掉就不用给整个域名开例外。
    static func streamURL(for id: Int) async throws -> URL {
        let json = try await get("/song/url/v1", ["id": String(id), "level": "exhigh"])
        guard
            let data = json["data"] as? [[String: Any]],
            let raw = data.first?["url"] as? String,
            !raw.isEmpty
        else { throw Failure.noStream }

        let https = raw.replacingOccurrences(of: "http://", with: "https://")
        guard let url = URL(string: https) else { throw Failure.noStream }
        return url
    }

    // MARK: - 请求

    private static func get(_ path: String, _ query: [String: String]) async throws -> [String: Any] {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else { throw Failure.badResponse }

        var request = URLRequest(url: url)
        // 上游偶尔慢吐字节，不设超时会一直挂着
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure.badResponse
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.badResponse
        }
        return json
    }
}

extension NeteaseAPI.Track {
    /// 转成可播放曲目。播放地址不在这里取 —— 交给 `PlayerModel.loadCurrent` 按需解析，
    /// 否则一搜 20 条就要发 20 个请求。
    var song: Song {
        Song(
            title: title,
            artist: artist,
            album: album.isEmpty ? "网易云音乐" : album,
            duration: duration,
            year: Calendar.current.component(.year, from: Date()),
            plays: 0,
            artworkName: "netease_\(id)",
            lyrics: [],
            source: .netease(id: id)
        )
    }
}
