import ActivityKit
import Foundation
import OSLog
import UIKit

enum PlaybackActivitySettings {
    static let enabledKey = "liveActivityEnabled"

    static var isEnabled: Bool {
        guard UserDefaults.standard.object(forKey: enabledKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: enabledKey)
    }
}

/// 实时活动的生命周期。App 负责 start / update / end，扩展负责渲染。
///
/// 一个活动贯穿整个播放会话。切歌只 update，不在后台重新 request。
@MainActor
final class PlaybackActivityManager {

    static let shared = PlaybackActivityManager()

    private let log = Logger(subsystem: "com.bhands.glassmusicplayer", category: "LiveActivity")

    private var activity: Activity<PlaybackActivityAttributes>?
    private var currentKey: String?
    private var userDismissed = false
    private var nextRequestAllowed = Date.distantPast
    private var pushID: UInt64 = 0
    private var motionClock: Double = 0
    private var lastMotionDate: Date?

    private struct SyncParams {
        var title: String
        var artist: String
        var songKey: String
        var artworkName: String
        var elapsed: Double
        var duration: Double
        var isPlaying: Bool
        var timestamp: Date
    }

    private var lastSync: SyncParams?
    private var artworkCache: [String: Data] = [:]
    private var downloading = Set<String>()
    private var fetchAttempted: [String: Date] = [:]

    private var pendingContent: ActivityContent<PlaybackActivityAttributes.ContentState>?
    private var deliveryRunning = false

    private var isEnabled: Bool {
        PlaybackActivitySettings.isEnabled && ActivityAuthorizationInfo().areActivitiesEnabled
    }

    init() {
        // App 被系统终止后，上一轮活动可能仍留在锁屏上。
        // 只清理启动时已经存在的活动，不会误伤本次会话新建的活动。
        let leftovers = Activity<PlaybackActivityAttributes>.activities
        guard !leftovers.isEmpty else { return }
        #if DEBUG
        Self.probe("启动清理残留活动 count=\(leftovers.count)")
        #endif
        Task {
            for leftover in leftovers {
                await leftover.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    #if DEBUG
    nonisolated static var verboseProbe: Bool { UserDefaults.standard.bool(forKey: "laProbe") }

    nonisolated static func probe(_ message: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("la_probe.log")
        let line = String(format: "%.3f ", Date().timeIntervalSince1970) + message + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
    #endif

    func sync(
        title: String,
        artist: String,
        songKey: String,
        artworkName: String,
        elapsed: Double,
        duration: Double,
        isPlaying: Bool,
        timestamp: Date
    ) {
        guard isEnabled else { return }

        lastSync = SyncParams(
            title: title,
            artist: artist,
            songKey: songKey,
            artworkName: artworkName,
            elapsed: elapsed,
            duration: duration,
            isPlaying: isPlaying,
            timestamp: timestamp
        )
        currentKey = songKey
        pushID &+= 1
        let now = Date()
        if isPlaying {
            let delta = lastMotionDate.map { now.timeIntervalSince($0) } ?? 0.25
            motionClock += min(max(delta, 0), 2)
            lastMotionDate = now
        } else {
            lastMotionDate = nil
        }

        let state = PlaybackActivityAttributes.ContentState(
            title: title,
            artist: artist,
            isPlaying: isPlaying,
            elapsed: elapsed,
            duration: duration,
            artworkData: encodedArtwork(for: songKey, name: artworkName),
            timestamp: timestamp,
            motionPhase: motionClock,
            pushID: pushID
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(900))

        if let activity {
            if activity.activityState == .dismissed {
                // 用户主动关闭后，本次播放会话不再自动重建。
                userDismissed = true
                self.activity = nil
                return
            }
            if activity.activityState == .ended {
                self.activity = nil
            } else {
                deliver(content)
                return
            }
        }

        guard !userDismissed, Date() >= nextRequestAllowed else { return }

        do {
            activity = try Activity.request(
                attributes: PlaybackActivityAttributes(),
                content: content
            )
            #if DEBUG
            Self.probe("request OK song=\(songKey) id=\(activity?.id ?? "-")")
            #endif
        } catch {
            log.error("实时活动启动失败: \(error.localizedDescription, privacy: .public)")
            activity = nil
            nextRequestAllowed = Date().addingTimeInterval(5)
        }
    }

    /// 串行投递并只保留最新状态，避免并发更新乱序或拖拽时更新洪水。
    private func deliver(_ content: ActivityContent<PlaybackActivityAttributes.ContentState>) {
        pendingContent = content
        guard !deliveryRunning else { return }
        deliveryRunning = true

        Task {
            while let next = pendingContent {
                pendingContent = nil
                guard let activity else { break }
                let started = Date()
                await Self.send(activity, next, watchdog: Self.updateWatchdog)
                let cost = Date().timeIntervalSince(started)
                if cost > 2 {
                    #if DEBUG
                    Self.probe("update WATCHDOG id=\(next.state.pushID) cost=\(String(format: "%.1f", cost))s —— 单次更新卡死，已放行下一轮")
                    #endif
                }
                #if DEBUG
                if Self.verboseProbe {
                    Self.probe("update sent id=\(next.state.pushID) phase=\(String(format: "%.2f", next.state.motionPhase)) title=\(next.state.title)")
                }
                #endif
            }
            deliveryRunning = false
        }
    }

    /// 单次 `activity.update` 的最长等待时间。
    ///
    /// 本 SDK 的 `update` 是 async **不抛错**的：一旦某次调用永远不返回
    /// （对已 ended 的活动补更新、request 后立刻 update 都踩过），
    /// 串行管道就永久卡死 —— 之后所有 `deliver()` 只更新信箱然后返回，
    /// 更新被静默丢弃，岛冻住且没有任何报错。看门狗保证管道最多被
    /// 卡住 2 秒，之后恢复吞吐。
    private static let updateWatchdog: Duration = .seconds(2)

    /// 带看门狗的 update：最多等 `watchdog`，超时也返回继续下一轮。
    private static func send(
        _ activity: Activity<PlaybackActivityAttributes>,
        _ content: ActivityContent<PlaybackActivityAttributes.ContentState>,
        watchdog: Duration
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = ResumeOnce(continuation)
            Task { await activity.update(content); once.resume() }
            Task {
                try? await Task.sleep(for: watchdog)
                once.resume()
            }
        }
    }

    /// update 和 sleep 竞争同一个 continuation，保证只恢复一次。
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        private let continuation: CheckedContinuation<Void, Never>

        init(_ continuation: CheckedContinuation<Void, Never>) {
            self.continuation = continuation
        }

        func resume() {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            continuation.resume()
        }
    }

    /// 结束当前播放会话。暂停只是临时状态，不应调用这里。
    func end(dismissalPolicy: ActivityUIDismissalPolicy = .immediate) {
        if let activity {
            Task {
                await activity.end(nil, dismissalPolicy: dismissalPolicy)
            }
        }
        self.activity = nil
        pendingContent = nil
        currentKey = nil
        lastSync = nil
        motionClock = 0
        lastMotionDate = nil
        // 设置页重新开启或开始下一场播放时允许创建新活动。
        userDismissed = false
    }

    private func encodedArtwork(for songKey: String, name: String) -> Data? {
        if let cached = artworkCache[songKey] {
            return cached
        }

        guard let image = coverImage(named: name) else {
            fetchArtwork(songKey: songKey, name: name)
            return nil
        }

        guard let data = Self.downscaledJPEG(from: image) else {
            log.error("封面压缩后仍超字节上限，放弃 song=\(songKey, privacy: .public)")
            return nil
        }

        if artworkCache.count > 6 {
            artworkCache.removeAll()
        }
        artworkCache[songKey] = data
        return data
    }

    private func fetchArtwork(songKey: String, name: String) {
        guard name.hasPrefix("http") else { return }
        guard !downloading.contains(songKey) else { return }
        if let last = fetchAttempted[songKey], Date().timeIntervalSince(last) < 5 { return }
        guard let url = URL(string: name) else { return }

        fetchAttempted[songKey] = Date()
        downloading.insert(songKey)

        Task {
            defer { downloading.remove(songKey) }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else { return }
                ImageCache.shared.store(image, for: url)

                guard currentKey == songKey, let params = lastSync, params.songKey == songKey else {
                    return
                }
                sync(
                    title: params.title,
                    artist: params.artist,
                    songKey: params.songKey,
                    artworkName: params.artworkName,
                    elapsed: params.elapsed,
                    duration: params.duration,
                    isPlaying: params.isPlaying,
                    timestamp: params.timestamp
                )
            } catch {
                log.error("封面下载失败: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func coverImage(named name: String) -> UIImage? {
        guard !name.isEmpty else { return nil }
        guard name.hasPrefix("http") else { return UIImage(named: name) }
        guard let url = URL(string: name) else { return nil }
        return ImageCache.shared.image(for: url)
    }

    private static func downscaledJPEG(from image: UIImage) -> Data? {
        let side: CGFloat = 48
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let render = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let square = render.image { _ in
            let scale = max(side / image.size.width, side / image.size.height)
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2)
            UIColor.black.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: side, height: side))
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }

        for quality in [0.55, 0.45, 0.35, 0.25] {
            if let data = square.jpegData(compressionQuality: quality), data.count <= 1800 {
                return data
            }
        }
        return nil
    }
}
