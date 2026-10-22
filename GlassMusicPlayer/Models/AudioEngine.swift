import AVFoundation
import MediaPlayer

/// 音频引擎：把 `AVPlayer` 包一层，负责四件事。
///
/// 1. **会话** —— `.playback` 分类，静音键拨到静音也能出声，锁屏不中断
/// 2. **进度** —— `addPeriodicTimeObserver` 每 0.25 秒回吐一次 0...1 的进度，
///    替换掉原来写死的 `progress`
/// 3. **锁屏信息** —— `MPNowPlayingInfoCenter`，锁屏/车机显示歌名、封面、进度
/// 4. **远程控制** —— `MPRemoteCommandCenter`，耳机双击、锁屏按钮
///
/// 刻意不加 `@MainActor`：`addPeriodicTimeObserver` 的回调是 `@Sendable`，
/// 加隔离反而要和 `assumeIsolated` 打架。所有回调都指定 `.main` 队列，
/// 调用方在 UI 线程用，不会跨线程改状态。
final class AudioEngine {

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    /// 当前播放项的 status 观察（用来接住"地址拿到了但放不出来"）
    private var itemObservation: NSKeyValueObservation?
    /// 用于进度换算的分母（0 时长会被抬到 1，避免除零）
    private var duration: Double = 1
    /// 真实时长。0 表示直播流 —— 锁屏按 live stream 展示，不显示进度。
    private var realDuration: Double = 0

    /// 调试：`-noNowPlaying 1` 跳过系统媒体注册（MPNowPlayingInfoCenter /
    /// MPRemoteCommandCenter）。用来实验「不注册 Now Playing 时，系统媒体岛
    /// 是否不再抢占灵动岛槽位」。关掉后锁屏/控制中心/耳机的系统集成消失，
    /// 但我们的实时活动锁屏卡片（带播放按钮）仍在。
    private let registersNowPlaying: Bool = {
        #if DEBUG
        return !UserDefaults.standard.bool(forKey: "noNowPlaying")
        #else
        return true
        #endif
    }()

    /// 进度回调（0...1），主队列
    var onProgress: ((Double) -> Void)?
    /// 一曲自然播完，主队列
    var onFinish: (() -> Void)?
    /// 播放项加载/播放失败（地址拿到了但放不出来），主队列
    var onLoadFailure: (() -> Void)?
    /// 远程控制（耳机 / 锁屏）触发的播放状态变化
    var onRemoteToggle: (() -> Void)?
    var onRemoteNext: (() -> Void)?
    var onRemotePrevious: (() -> Void)?

    init() {
        configureSession()
        addTimeObserver()
        if registersNowPlaying {
            configureRemoteCommands()
        }
    }

    // MARK: - 会话

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        // .playback：静音键不影响播放，且支持后台继续
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    // MARK: - 装载与传输控制

    /// 装载一首歌。`duration` 用曲目数据里的值，避免依赖资源元信息。
    /// 传 0 表示直播流。
    func load(url: URL, duration: Double, autoplay: Bool) {
        realDuration = duration
        self.duration = max(duration, 1)
        let item = AVPlayerItem(url: url)
        observeItem(item)
        player.replaceCurrentItem(with: item)
        player.seek(to: .zero)
        if autoplay { play() }
    }

    /// 盯住播放项的 status。
    ///
    /// **`.failed` 必须有人接**：网易云的地址可能拿到了却放不出来
    /// （403 / 过期 / 版权拦截 / 解码失败）。没人接的话播放器会停在
    /// "什么都没在播、但 isPlaying 还是 true"的僵尸态 —— 进度冻结、
    /// 推送逐字节相同，灵动岛封面看起来就是"冻住了"。
    private func observeItem(_ item: AVPlayerItem) {
        itemObservation?.invalidate()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failObserver { NotificationCenter.default.removeObserver(failObserver) }

        itemObservation = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            guard let self, observedItem.status == .failed, self.player.currentItem === observedItem else { return }
            DispatchQueue.main.async {
                self.onLoadFailure?()
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            guard let self, let item, self.player.currentItem === item else { return }
            self.onFinish?()
        }

        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            guard let self, let item, self.player.currentItem === item else { return }
            self.onLoadFailure?()
        }
    }

    func play() {
        // 会话可能被来电等打断过，播放前重新激活
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
    }

    func pause() {
        player.pause()
    }

    func seek(to seconds: Double) {
        let target = CMTime(seconds: max(0, min(seconds, duration)), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: - 观察

    private func addTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            let value = min(max(seconds / self.duration, 0), 1)
            self.onProgress?(value)
        }
    }

    // MARK: - 锁屏与远程控制

    /// 同步锁屏信息。切歌、暂停、拖进度时都要调。
    func updateNowPlaying(
        title: String,
        artist: String,
        artworkName: String,
        elapsed: Double,
        isPlaying: Bool
    ) {
        guard registersNowPlaying else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist
        ]
        if realDuration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = realDuration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
            info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        } else {
            // 直播流：没有时长，告诉系统这是 live
            info[MPNowPlayingInfoPropertyIsLiveStream] = true
        }
        if let cover = coverImage(named: artworkName) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: cover.size) { _ in cover }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // 远程封面还没下过：先不带图，下完再补上。
        // 之前这里只用 UIImage(named:)，而它只认本地资源 ——
        // 网易云曲目的 artworkName 是 URL，锁屏上一直没有封面。
        if coverImage(named: artworkName) == nil,
           artworkName.hasPrefix("http"),
           let url = URL(string: artworkName) {
            Task { @MainActor in
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = UIImage(data: data) else { return }
                ImageCache.shared.store(image, for: url)
                self.attachArtwork(image)
            }
        }
    }

    /// 把封面补进已有的锁屏信息里，不动其它字段。
    private func attachArtwork(_ image: UIImage) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// 本地资源按名字取；远程封面走内存缓存（UI 里通常已经下过了）。
    private func coverImage(named name: String) -> UIImage? {
        guard name.hasPrefix("http") else { return UIImage(named: name) }
        guard let url = URL(string: name) else { return nil }
        return ImageCache.shared.image(for: url)
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.onRemoteToggle?()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.onRemoteToggle?()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.onRemoteToggle?()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.onRemoteNext?()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.onRemotePrevious?()
            return .success
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failObserver { NotificationCenter.default.removeObserver(failObserver) }
        itemObservation?.invalidate()
    }
}
