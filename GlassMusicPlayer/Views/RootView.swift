import SwiftUI

/// 根容器。
///
/// 结构只有三层：**稳固的内容底 → 可滚动内容 → 悬浮玻璃 chrome**。
/// 迷你播放条和 Tab Bar 放进同一个 `GlassEffectContainer`，
/// 它们会像一滴水一样相互融合，而不是两块玻璃硬摞着。
struct RootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var player = PlayerModel()
    /// 歌单的远程曲库（网易云）。本地只有 8 首，撑不起 30 首的歌单。
    @State private var playlists = PlaylistStore()
    /// 音乐库：先用打包音轨，随后按清单从网易云解析真实曲目
    @State private var library = LibraryStore()
    @State private var selection = DebugLaunch.initialTab
    @State private var showsNowPlaying = DebugLaunch.opensNowPlaying

    /// 一闪而过的提示文案（"已经是第一首了"）
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?

    private let tabs: [(icon: String, title: String)] = [
        ("house.fill", "现在就听"),
        ("square.stack.fill", "音乐库"),
        ("magnifyingglass", "搜索"),
        ("person.crop.circle.fill", "我的")
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selection {
                case 0:  HomeView(selection: $selection)
                case 1:  LibraryView()
                case 2:  SearchView(isModal: false)
                default: ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomChrome
        }
        .overlay(alignment: .bottom) {
            if let toast {
                ToastPill(message: toast)
                    .padding(.bottom, 150)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity)
                    )
            }
        }
        .environment(player)
        .environment(playlists)
        .environment(library)
        .environment(NeteaseSession.shared)
        // 内容与 chrome 一起延伸到屏幕底部。
        // iOS 26 的浮动 Tab Bar 就贴在这个位置：下方只留 ~16pt 给 Home Indicator，
        // 而不是留一整条 34pt 的安全区 —— 那样 Tab Bar 会像悬在内容中间。
        .ignoresSafeArea(.container, edges: .bottom)
        // 这套设计以「柔和浅色」为基准：内容区是浅色分组底，玻璃是浅色材质。
        // 深色外观下语义色会自动反相，但对比与层次需要单独调，这里先锁定浅色。
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $showsNowPlaying) {
            NowPlayingView()
                .environment(player)
                .presentationBackground(.clear)
        }
        .task {
            if DebugLaunch.showsToast {
                // 截图用：给足时间，避免还没拍到就淡出了
                showToast("已经是第一首了", seconds: 20)
            }
            // 歌单的真实曲库（网易云）。失败会静默退回本地选曲。
            await playlists.loadAll()
            await library.load()
            player.adoptLibrary(library.songs)
            // 有本地 cookie 的话顺手刷一次账号信息（cookie 失效会自动清掉）
            await NeteaseSession.shared.refreshAccount()
        }
    }

    // MARK: - 轻提示

    /// 弹一条提示，默认 1.8 秒。连点时取消上一个计时，避免前一条把后一条提前关掉。
    private func showToast(_ message: String, seconds: Double = 1.8) {
        withAnimation(reduceMotion ? nil : LiquidTheme.Motion.snappy) {
            toast = message
        }
        AccessibilityNotification.Announcement(message).post()

        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : LiquidTheme.Motion.snappy) {
                toast = nil
            }
        }
    }

    // MARK: - 悬浮 chrome

    private var bottomChrome: some View {
        // 间距 6pt：迷你条贴着 Tab Bar，像 Apple Music 那样。
        VStack(spacing: 6) {
            MiniPlayerBar(
                song: player.current,
                isPlaying: player.isPlaying,
                onTap: { showsNowPlaying = true },
                onPrevious: {
                    if !player.previous() {
                        showToast("已经是第一首了")
                    }
                },
                onPlayPause: { player.togglePlayPause() },
                onNext: {
                    if !player.next() {
                        showToast("已经是最后一首了")
                    }
                }
            )

            LiquidTabBar(items: tabs, selection: $selection)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
    }
}

#Preview {
    RootView()
}

// MARK: - 截图 / UI 自动化的启动参数

/// 全部由 `#if DEBUG` 保护，Release 构建里直接返回默认值。
/// 用法：
/// ```
/// xcrun simctl launch booted com.example.GlassMusicPlayer -tab 1
/// xcrun simctl launch booted com.example.GlassMusicPlayer -nowPlaying 1
/// xcrun simctl launch booted com.example.GlassMusicPlayer -tab 0 -playlist 1
/// xcrun simctl launch booted com.example.GlassMusicPlayer -tab 1 -toast 1
/// ```
enum DebugLaunch {

    static var initialTab: Int {
        #if DEBUG
        let value = UserDefaults.standard.integer(forKey: "tab")
        return (0...3).contains(value) ? value : 0
        #else
        return 0
        #endif
    }

    static var opensNowPlaying: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "nowPlaying")
        #else
        return false
        #endif
    }

    /// `-toast 1` 启动即弹一次提示，用来截图验证轻提示的样式。
    static var showsToast: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "toast")
        #else
        return false
        #endif
    }

    /// `-radio N` 启动即播放第 N 个网络电台（1 起），用来验证直播流。
    static var radioIndex: Int {
        #if DEBUG
        return UserDefaults.standard.integer(forKey: "radio")
        #else
        return 0
        #endif
    }

    /// `-detail quality|downloads|about|account` 启动即打开「我的」页对应的详情浮层。
    /// 只决定"打开哪一页"，不改变任何交互行为。
    static var profileDetail: String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "detail")
        #else
        return nil
        #endif
    }

    /// `-lyrics 1` 启动即展开歌词视图，用来截图验证歌词解析。
    static var opensLyrics: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "lyrics")
        #else
        return false
        #endif
    }

    /// `-playlist N` 直接打开第 N 个歌单（1 起）。截图时用来逐张验证封面。
    static var playlistIndex: Int {
        #if DEBUG
        return UserDefaults.standard.integer(forKey: "playlist")
        #else
        return 0
        #endif
    }

    static func flag(_ key: String) -> Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: key)
        #else
        return false
        #endif
    }
}
