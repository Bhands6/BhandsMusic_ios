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
    /// 每次推送严格递增 —— 只喂探针日志。Widget 不消费它，不进 ContentState。
    private var pushID: UInt64 = 0
    /// 上一场会话结束时可能还挂在锁屏上的活动（`.after` 策略的残卡）。
    /// 新会话 request 之前先把它收掉，否则锁屏会叠两张卡。
    private var lingering: Activity<PlaybackActivityAttributes>?

    private struct SyncParams {
        var title: String
        var artist: String
        var songKey: String
        var artworkName: String
        var elapsed: Double
        var duration: Double
        var isPlaying: Bool
        var timestamp: Date
        var playClock: Double
        var playingSince: Date?
    }

    private var lastSync: SyncParams?
    private var artworkCache: [String: Data] = [:]
    private var downloading = Set<String>()
    private var fetchAttempted: [String: Date] = [:]

    private var pendingContent: ActivityContent<PlaybackActivityAttributes.ContentState>?
    /// 排队中的收尾。end 也走串行管道 —— 保证终态推送先落地、end 后执行，
    /// 否则队列播完时锁屏上会留一张定格在「正在播放」的残卡。
    private var pendingEnd: (activity: Activity<PlaybackActivityAttributes>, policy: ActivityUIDismissalPolicy)?
    private var deliveryRunning = false

    private var isEnabled: Bool {
        PlaybackActivitySettings.isEnabled && ActivityAuthorizationInfo().areActivitiesEnabled
    }

    init() {}

    /// 冷启动时收掉上一次会话残留在锁屏上的卡片。
    ///
    /// App 被杀后活动不会跟着消失。这个清理**不能**搭在第一次 `sync()` 上 ——
    /// 会话开始前 `syncLiveActivity()` 有门卫不推送，不播放就永远不清，
    /// 所以由 `PlayerModel` 启动时无条件调这里。
    func cleanupOnLaunch() {
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
        timestamp: Date,
        playClock: Double = 0,
        playingSince: Date? = nil
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
            timestamp: timestamp,
            playClock: playClock,
            playingSince: playingSince
        )
        currentKey = songKey
        pushID &+= 1

        let state = PlaybackActivityAttributes.ContentState(
            title: title,
            artist: artist,
            isPlaying: isPlaying,
            elapsed: elapsed,
            duration: duration,
            artworkData: encodedArtwork(for: songKey, name: artworkName),
            timestamp: timestamp,
            playClock: playClock,
            playingSince: playingSince
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

        // 上一场会话可能还留着没到期的残卡（`.after` 策略），或者还压在管道里
        // 没执行完的收尾 —— 新卡出现前先收掉，避免锁屏叠两张卡。
        let staleCards = [lingering, pendingEnd?.activity].compactMap { $0 }
        lingering = nil
        if !staleCards.isEmpty {
            pendingEnd = nil
            Task {
                for stale in staleCards {
                    await stale.end(nil, dismissalPolicy: .immediate)
                }
            }
        }

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

    /// 投递一版新内容：只进信箱，由串行管道慢慢发（见 `pump`）。
    private func deliver(_ content: ActivityContent<PlaybackActivityAttributes.ContentState>) {
        pendingContent = content
        pump()
    }

    /// 「信箱 + 单飞」串行管道：并发恒 1、投递天然有序、信箱里只留最新。
    ///
    /// 收尾（end）也排进同一条管道 —— 终态推送一定先落地、end 一定后执行。
    /// 乱序、更新洪水、卡死都只能伤到一张卡片的时间线，伤不到顺序。
    private func pump() {
        guard !deliveryRunning else { return }
        deliveryRunning = true

        Task {
            while true {
                // 没有当前活动时，若还挂着收尾，终态要落在那张待收的卡上。
                guard let target = activity ?? pendingEnd?.activity else { break }

                if let next = pendingContent {
                    pendingContent = nil
                    let timedOut = await Self.withWatchdog(Self.updateWatchdog) {
                        await target.update(next)
                    }
                    if timedOut {
                        retireStuckActivity(target)
                        break
                    }
                    #if DEBUG
                    if Self.verboseProbe {
                        Self.probe("update sent id=\(pushID) playing=\(next.state.isPlaying) title=\(next.state.title)")
                    }
                    #endif
                    continue
                }

                if let end = pendingEnd {
                    pendingEnd = nil
                    let timedOut = await Self.withWatchdog(Self.updateWatchdog) {
                        await end.activity.end(nil, dismissalPolicy: end.policy)
                    }
                    if timedOut {
                        retireStuckActivity(end.activity)
                    }
                    continue
                }

                break
            }
            deliveryRunning = false
        }
    }

    /// 单次 update / end 的最长等待时间。
    ///
    /// 本 SDK 的 `update` / `end` 是 async **不抛错**的：一旦某次调用永远不返回
    /// （对已 ended 的活动补更新、request 后立刻 update 都踩过），
    /// 串行管道就永久卡死 —— 之后所有 `pump()` 只更新信箱然后返回，
    /// 更新被静默丢弃，岛冻住且没有任何报错。看门狗保证管道最多被
    /// 卡住 2 秒，之后恢复吞吐。
    private static let updateWatchdog: Duration = .seconds(2)

    /// 看门狗赛跑：跑 `body`，最多等 `watchdog`。
    /// - Returns: `true` 表示超时 —— `body` 至今没有返回，别再等它。
    private static func withWatchdog(
        _ watchdog: Duration,
        _ body: @escaping @Sendable () async -> Void
    ) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = ResumeOnce(continuation)
            Task {
                await body()
                once.resume(with: false)
            }
            Task {
                try? await Task.sleep(for: watchdog)
                once.resume(with: true)
            }
        }
    }

    /// 看门狗超时：这次调用卡死了。继续往同一个活动上投递只会越积越多，
    /// 而且卡死后迟到的旧状态可能落在新状态之后、把新内容覆盖回旧值 ——
    /// 干脆放弃这张卡，下次 `sync()` 按需重 request 一张新的。
    /// 如果卡死是因为用户划掉了卡片（`.dismissed`），按「用户关闭」处理，不重建。
    private func retireStuckActivity(_ stuck: Activity<PlaybackActivityAttributes>) {
        #if DEBUG
        Self.probe("update WATCHDOG id=\(pushID) state=\(stuck.activityState) —— 放弃该活动，下次 sync 按需重建")
        #endif
        if stuck.activityState == .dismissed {
            userDismissed = true
        }
        if activity?.id == stuck.id { activity = nil }
        if pendingEnd?.activity.id == stuck.id { pendingEnd = nil }
        if lingering?.id == stuck.id { lingering = nil }
        pendingContent = nil
        nextRequestAllowed = Date().addingTimeInterval(2)
        // 连 end 都不等 —— 卡死过的活动 end 也可能不返回，不能让它堵住管道。
        Task { await stuck.end(nil, dismissalPolicy: .immediate) }
    }

    /// body 和 sleep 竞争同一个 continuation，保证只恢复一次。
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        private let continuation: CheckedContinuation<Bool, Never>

        init(_ continuation: CheckedContinuation<Bool, Never>) {
            self.continuation = continuation
        }

        func resume(with timedOut: Bool) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            continuation.resume(returning: timedOut)
        }
    }

    /// 结束当前播放会话。暂停只是临时状态，不应调用这里。
    ///
    /// 收尾会排进串行管道，排在它之前入箱的终态推送后面。
    func end(dismissalPolicy: ActivityUIDismissalPolicy = .immediate) {
        // 之前已经排了收尾（比如队列刚播完）—— 作废它，按本次调用重排。
        // 只清不补的话这张卡就永远没人收了。
        if let queued = pendingEnd {
            pendingEnd = nil
            Task { await queued.activity.end(nil, dismissalPolicy: .immediate) }
        }
        guard let activity else {
            pendingContent = nil
            resetSession()
            return
        }
        self.activity = nil
        // 记下这张卡：若策略是 .after，它会继续挂在锁屏上一段时间，
        // 下一个会话 request 之前要能找到它、收掉它。
        lingering = activity
        pendingEnd = (activity: activity, policy: dismissalPolicy)
        resetSession()
        pump()
    }

    private func resetSession() {
        currentKey = nil
        lastSync = nil
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
                    timestamp: params.timestamp,
                    playClock: params.playClock,
                    playingSince: params.playingSince
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
