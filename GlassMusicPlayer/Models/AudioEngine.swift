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
    private var duration: Double = 1

    /// 进度回调（0...1），主队列
    var onProgress: ((Double) -> Void)?
    /// 一曲自然播完，主队列
    var onFinish: (() -> Void)?
    /// 远程控制（耳机 / 锁屏）触发的播放状态变化
    var onRemoteToggle: (() -> Void)?
    var onRemoteNext: (() -> Void)?
    var onRemotePrevious: (() -> Void)?

    init() {
        configureSession()
        addTimeObserver()
        observeFinish()
        configureRemoteCommands()
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
    func load(url: URL, duration: Double, autoplay: Bool) {
        self.duration = max(duration, 1)
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.seek(to: .zero)
        if autoplay { play() }
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

    private func observeFinish() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onFinish?()
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
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let cover = UIImage(named: artworkName) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: cover.size) { _ in cover }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
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
    }
}
