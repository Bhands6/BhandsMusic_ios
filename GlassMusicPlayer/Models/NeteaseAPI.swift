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
        /// 封面地址（搜索接口不返回，靠 `/song/detail` 补）
        var cover: URL?

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

    /// 新歌速递。「每日推荐」用它 —— 搜索某个关键词是搜不出"推荐"的。
    /// 这个接口的返回结构和 `/search` 不同，曲目信息藏在 `song` 里。
    static func newsong(limit: Int = 30) async throws -> [Track] {
        let json = try await get("/personalized/newsong", ["limit": String(limit)])
        guard let items = json["result"] as? [[String: Any]] else { throw Failure.badResponse }

        return items.compactMap { item in
            guard let inner = item["song"] as? [String: Any],
                  let id = inner["id"] as? Int,
                  let name = inner["name"] as? String else { return nil }

            let artists = (inner["artists"] as? [[String: Any]])?
                .compactMap { $0["name"] as? String }
                .joined(separator: " / ") ?? "未知艺人"

            let album = inner["album"] as? [String: Any]
            let ms = inner["duration"] as? Double ?? 0
            let pic = (album?["picUrl"] as? String) ?? (item["picUrl"] as? String)

            return Track(
                id: id,
                title: name,
                artist: artists,
                album: album?["name"] as? String ?? "",
                duration: ms / 1000,
                cover: pic.flatMap { URL(string: $0.replacingOccurrences(of: "http://", with: "https://")) }
            )
        }
    }

    /// 批量补封面。`/search` 只给 `picId` 不给地址，`/song/detail` 才有 `al.picUrl`。
    /// 一次传多个 id，别一条一条来。
    static func covers(ids: [Int]) async throws -> [Int: URL] {
        guard !ids.isEmpty else { return [:] }
        let json = try await get("/song/detail", ["ids": ids.map(String.init).joined(separator: ",")])
        guard let songs = json["songs"] as? [[String: Any]] else { return [:] }

        var result: [Int: URL] = [:]
        for song in songs {
            guard let id = song["id"] as? Int,
                  let raw = (song["al"] as? [String: Any])?["picUrl"] as? String,
                  let url = URL(string: raw.replacingOccurrences(of: "http://", with: "https://"))
            else { continue }
            result[id] = url
        }
        return result
    }

    /// 取歌词并解析成时间轴。
    ///
    /// `/lyric` 返回的是 LRC 文本，形如 `[00:12.34]歌词`；
    /// 一行可能有多个时间戳（`[00:12.34][01:20.56]副歌`），都要展开。
    /// 返回空数组表示这首歌确实没有歌词（纯音乐）。
    static func lyrics(for id: Int) async throws -> [LyricLine] {
        let json = try await get("/lyric", ["id": String(id)])
        guard let raw = (json["lrc"] as? [String: Any])?["lyric"] as? String, !raw.isEmpty else {
            return []
        }
        return parseLRC(raw)
    }

    /// LRC 解析。只认 `[mm:ss.xx]` 这种数字时间戳，
    /// `[ti:]` / `[ar:]` / `[by:]` 这类元信息会被正则自然跳过。
    static func parseLRC(_ raw: String) -> [LyricLine] {
        let pattern = try? NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#)
        guard let pattern else { return [] }

        var lines: [LyricLine] = []
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let range = NSRange(line.startIndex..., in: line)

            let matches = pattern.matches(in: line, range: range)
            guard !matches.isEmpty else { continue }

            // 去掉所有时间戳，剩下的就是歌词文本
            let text = pattern.stringByReplacingMatches(in: line, range: range, withTemplate: "")
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            for match in matches {
                guard let minuteRange = Range(match.range(at: 1), in: line),
                      let secondRange = Range(match.range(at: 2), in: line),
                      let minutes = Double(line[minuteRange]),
                      let seconds = Double(line[secondRange])
                else { continue }

                // 毫秒部分可能是 2 位（厘秒）或 3 位
                var fraction = 0.0
                if let msRange = Range(match.range(at: 3), in: line), let raw = Double(line[msRange]) {
                    fraction = raw / pow(10, Double(String(line[msRange]).count))
                }
                lines.append(LyricLine(text: text, time: minutes * 60 + seconds + fraction))
            }
        }

        return lines.sorted { $0.time < $1.time }
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
    ///
    /// `artworkName` 直接放封面 URL（没有就放 id），`ArtworkView` 认得 `http` 开头的名字。
    var song: Song {
        Song(
            title: title,
            artist: artist,
            album: album.isEmpty ? "网易云音乐" : album,
            duration: duration,
            year: Calendar.current.component(.year, from: Date()),
            plays: 0,
            artworkName: cover?.absoluteString ?? "netease_\(id)",
            lyrics: [],
            source: .netease(id: id)
        )
    }
}
