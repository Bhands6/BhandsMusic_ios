# BhandsMusic · 液态玻璃音乐播放器（SwiftUI）

> 仓库：https://github.com/Bhands6/BhandsMusic_ios

一套可运行的 iOS 音乐播放器高保真 UI，视觉语言为 **iOS 26 Liquid Glass**。
七个界面全部编译通过并在 iPhone 18 Pro 模拟器上逐屏截图验证。

```bash
open /Users/bhands/iOS_project/GlassMusicPlayer.xcodeproj
```

双击 → 选模拟器 → `⌘R`。零配置。

> 显示名 **BhandsMusic**、版本 **v1.0.0**。
> 显示名在 `project.pbxproj` 的 `INFOPLIST_KEY_CFBundleDisplayName`（Debug / Release 两处都要改）；
> 版本号是「我的 → 关于」里的一行文案，与 Info.plist 的 `CFBundleShortVersionString` 目前并未联动。

> 最低部署目标 **iOS 26.0** —— 直接调用系统原生的 `.glassEffect` / `GlassEffectContainer` /
> `.scrollEdgeEffectStyle`，不是手搓毛玻璃。

---

## 一、设计原则（对应设计约束）

整套 UI 由五条硬规则撑起来，写代码时任何一处都不该破例：

| # | 规则 | 落点 |
|---|---|---|
| 1 | **玻璃分层** | chrome 用 `chromeTint`/`dockTint`；内容面板用 `panelFill` + 细亮边（原为实底，后按需求改为玻璃） |
| 2 | **不叠玻璃** | 两块玻璃之间必有内容或留白；头部胶囊里的按钮不再套玻璃圆底 |
| 3 | **对比优先** | 正文永远用 `label` 级对比度，不靠材质"透"出来的背景撑可读性 |
| 4 | **同心圆角** | 内层圆角 = 外层圆角 − 内边距 |
| 5 | **动效可关** | 所有滚动联动读 `accessibilityReduceMotion`，关掉后直接跳变 |

### 内容区稳固 / chrome 浮动

页面永远是同一个三层结构：

```
稳固的内容底（SoftCanvas，不随滚动变化）
  └─ 可滚动内容（玻璃面板）
       └─ 悬浮玻璃 chrome（头部胶囊 / 迷你播放条 / Tab Bar）
```

动的是 chrome，不是地面 —— 这是「内容区保持稳固背景，浮动导航和工具栏覆盖其上」的实现方式。

### 底部 chrome 的位置

Tab Bar 底边距屏幕底 **16pt**（不是安全区的 34pt）。

iOS 26 里底部工具栏如果按安全区约束，是**不会**延伸到屏幕边缘的（iOS 18 会），
结果就是 Tab Bar 悬在内容中间、下方露出一整条彩色内容。所以根容器加了
`.ignoresSafeArea(.container, edges: .bottom)`，只给 Home Indicator 留 16pt。

同时叠了一层 170pt 的底部渐隐（`canvas` 色）：没有它，实底卡片会以硬边从玻璃下面穿过去，
Tab Bar 看起来像"浮在内容上"而不是"贴底"。

内容区的底部留白 `Spacing.bottomSafe = 148` = 迷你条 50 + 间距 6 + Tab Bar 64 + 底部 16 + 余量。

迷你条和 Tab Bar 之间只留 **6pt** —— Apple Music 就是贴着的。中间这条缝会把滚动内容
透出来，正好说明"浮动 chrome 覆盖在内容上"。两个胶囊的圆角边界仍然分明，不会粘成一坨。

### 层级随滚动变化

**大标题和胶囊在同一行**（标题靠左、胶囊靠右），所以顶部没有一条独立的导航栏空带 ——
内容从 `.padding(.top, 14)` 就开始，标题直接顶到状态栏下面。

`ScreenHeader` 的胶囊**贴合内容宽度**，两种状态：

| 状态 | 表现 |
|---|---|
| **静止** | 右上角一枚只装操作按钮的小胶囊（不会出现"一整条空胶囊"这种一眼是 bug 的形态） |
| **滚动 > 10pt** | 屏幕标题从左侧淡入，胶囊向左生长，大标题同时滚走 |

阈值只给 10pt —— 大标题一开始上移，行内标题就该跟着出现，这才是 iOS 的行为。
滚动距离由 `onScrollGeometryChange` 读取，不依赖任何手写 PreferenceKey。

> 想直接看展开态：`xcrun simctl launch booted com.example.GlassMusicPlayer -scrollBottom 1`
> 会以「滚到底」启动，胶囊是展开的。

---

## 二、视觉系统

### 材质

| 用途 | 实现 |
|---|---|
| chrome 玻璃 | `.glassEffect(.regular, in: .rect(cornerRadius:))` |
| chrome 加压 | `.tint(chromeTint)` / `.tint(dockTint)` —— 见下方两档染色的区别 |
| 可点玻璃 | `.interactive()` —— 按下时系统自己给反馈 |
| 细亮边 | `glassEdge(cornerRadius:)` / `glassEdgeCapsule()` —— 左上亮 → 右下暗的描边 |
| 内容面板 | `glassPanel()`：`panelFill` 实底 + `glassEffect` 光泽 + `glassEdge` 细亮边 |
| 滚动边缘 | `.scrollEdgeEffectStyle(.soft, for: .bottom)` |

**三档材质，按"背后压着什么"来选：**

| 令牌 | 值 | 用在哪 |
|---|---|---|
| `chromeTint` | `systemBackground` @ 0.42（白） | 顶部悬浮胶囊 |
| `controlFill` + `controlTint` | 实底 `#ECEEFF` + 染色 | **迷你播放条** |
| `Glass.clear` | 不染色 | **Tab Bar** |

**迷你播放条和 Tab Bar 刻意用不同材质：**

- 迷你条承载歌名 + 艺人两行字，背后又有封面卡片滚过去 —— 必须**垫一层实底**
  （`controlFill`），玻璃只负责表面的光泽和边缘。只靠 `Glass.regular` 是挡不住的。
- Tab Bar 对齐 iOS 26 原生 Dock 的观感，走 `clear`，几乎全透明。

> ⚠️ **`Glass.tint` 不是不透明度旋钮。** 调到 0.95 背后的文字照样透上来。
> 要真正"不透文字"只有一条路：在玻璃**下面**垫实底。
>
> ⚠️ 控制栏也不能用纯白磨砂 —— 压在浅色内容面板上会连成一整块，
> 看起来像"列表和播放器长在了一起"。所以底色带一点蓝紫（`#ECEEFF`），
> 再加一道 `shadow(black 0.09, y 5)` 把它抬起来。
>
> 试过把 `chromeTint` 全局提到 0.52 去解决迷你条，结果**顶部胶囊被连带变成白板**。
> 不同位置的 chrome 背后压的东西不一样，**必须一档一个令牌**。

### 迷你播放条

单行结构：`[封面] 歌名 / 艺人 …… ⏮ ⏸ ⏭`，高度 **50pt**。

```
┌──────────────────────────────┐
│ [封面] 歌名 / 艺人   ⏮  ⏸  ⏭ │
└──────────────────────────────┘
```

左侧（封面 + 文字）是 `Button`，点按打开正在播放；右侧三个传输键放一个 **`spacing: 0` 的 HStack** ——
每个按钮本身有 44pt 触控框、图标居中，视觉间距已经够了，分开排能给歌名多留 24pt。

> **进度条已按要求移除。** 之前这里有一条 `MiniProgressBar`（4pt 轨道 + 圆点、可拖拽），
> 加进去后迷你条涨到 72pt、`bottomSafe` 也跟着改到 162。
> 移除后两者都回到 50 / 148。要恢复的话，`MiniProgressBar` 这个组件在 git 历史里。

**左右内边距要算上胶囊圆角。** 胶囊 `cornerRadius = 26`，封面高 38、上边距 6 ——
在那个高度上圆角已经向内收了 9.4pt（`26 − √(26² − 20²)`），
所以 `leading` 至少要 10 才不切角，实际取 **14**；`trailing` 取 10，右侧两个按钮才不顶到边。

Tab Bar 另加一道 **1pt 白线**（白 0.96 → 0.42 渐变）勾出胶囊轮廓 —— 这是参考图里
"边界带线条"的落点。0.5pt 在浅底上根本看不见。

`chromeTint = Color(uiColor: .systemBackground).opacity(0.42)`。

**这个值很敏感，调之前先看这条**：`Glass.tint` 是给玻璃**着色**的，不是不透明度旋钮。

- `0.62` → 玻璃变成一块白板，背后没东西可透，**玻璃感全失**
- `0.26` → 很透，但灰色标签压在彩色卡片上对比不够
- `0.42` → 平衡点：仍能看见背后的色块，文字也立得住

同理，**不要在 chrome 下面加整片渐隐**。那样等于把玻璃背后的内容洗白，
玻璃同样退化成白板 —— 这是本项目踩过的坑。

### 背景

`SoftCanvas` = 浅薰衣草底 + 四团柔光斑，只影响四个 Tab 页（正在播放 / 队列用的是封面暗色背景，不受影响）。

| 层 | 值 |
|---|---|
| 底色 | `#F2F1FB` → `#E8E7F7` 纵向渐变 |
| 光斑 | 右上 `#7C6BF0` .32 / 左上 `#A78BFA` .26 / 左下 `#818CF8` .22 / 右下 `#C4B5FD` .20 |

光斑压在四角，**中间留干净区域给正文** —— 这是为了守住"文字对比优先"。

> 用 `RadialGradient` 而不是 `Circle().blur()`：视觉上一样柔和，但纯 GPU 绘制，
> 静态背景不会持续付高斯模糊的开销。

全部走系统语义色（`Color(uiColor:)`），深浅色自动适配：
`canvas` / `card` / `label` / `secondary` / `separator`，强调色 `Color.indigo`。

### 字体

全部走 `Font.TextStyle`（`.largeTitle` / `.title3` / `.body` / `.caption` …），
**动态字体自动缩放**，不写死 pt。

### 圆角

`sheet 28` / `card 22` / `tile 16` / `control 14` / `dock 26` / `pill ∞`

### 内容面板（玻璃底框）

原来所有卡片是实底（`solidCard`：白 + 0.5pt 描边）。后来按要求改成
**参考分段控件那种玻璃底框** —— `glassPanel()`：

```swift
content
    .background(RoundedRectangle(cornerRadius: cornerRadius).fill(LiquidTheme.Palette.panelFill))
    .liquidGlass(cornerRadius: cornerRadius)
    .glassEdge(cornerRadius: cornerRadius)
```

`panelFill = #E9E7F6`。

**为什么是实底而不是染色 —— 这是本项目最反直觉的一条发现：**

> **`Glass.regular` 的亮度会随面积变化。** 同一份材质，小胶囊（分段控件）渲染成 ~232，
> 大面板渲染成 ~249。光靠 `tint` 永远对不齐 —— 而 tint 本身也不是线性旋钮
> （0.28 几乎没效果，0.55 直接冲到纯白 255）。
>
> 所以内容面板改成"固定底色 + 玻璃光泽"：`panelFill` 保证色调稳定，玻璃只负责高光和边缘。
> 分段控件同理，直接 `Capsule().fill(panelFill)` + 细亮边，**不叠 glassEffect** ——
> 小面积玻璃会把底色压暗约 25 级，和面板放一起必然打架。

> ⚠️ 这一版**推翻了最初"正文卡片一律实底"的约束**。取舍：
> 整页玻璃更统一、更"液态"，但卡片与背景的层次比实底弱，
> 全靠 `glassEdge` 那道 0.5pt 亮边撑住边界。如果哪天觉得"糊成一片"，先调 `panelFill` 的明度。

### 轻提示

`ToastPill`：实底 + 玻璃光泽 + 投影，1.8 秒后自动淡出。

| 触发 | 文案 |
|---|---|
| 在第一首点「上一曲」 | 已经是第一首了 |

**`previous()` 改成返回 `Bool`**（`@discardableResult`）：`false` 表示"已经是第一首、什么也没发生"，
调用方据此决定弹不弹提示。

> ⚠️ 注意：播过 3 秒后点上一曲是**回到本曲开头**（和真实播放器一致），
> 这算"有动作"，所以**不弹提示**。只有真正无操作时才会提示。

连点会取消上一个计时器，避免前一条把后一条提前关掉。
`AccessibilityNotification.Announcement` 让 VoiceOver 也能读到。

### 音频播放

**真的在放声音**，不是模拟。

| 文件 | 职责 |
|---|---|
| `Models/AudioEngine.swift` | 包一层 `AVPlayer`：会话、时间观察、锁屏信息、远程控制 |
| `Models/MusicLibrary.swift` | `PlayerModel` 把 UI 状态映射到引擎 |

**四件必须做的事**（缺一样都会出问题）：

1. **`AVAudioSession` 配 `.playback`** —— 不配的话静音键一拨就没声，锁屏也停
2. **`addPeriodicTimeObserver`** —— 每 0.25 秒回吐 0...1 进度，替换掉原来写死的 `progress`
3. **`MPNowPlayingInfoCenter`** —— 锁屏 / 车机显示歌名、封面、进度
4. **`MPRemoteCommandCenter`** —— 耳机双击、锁屏按钮能控制

**后台播放**需要在 Info.plist 声明 `UIBackgroundModes: [audio]`。
工程走的是 `GENERATE_INFOPLIST_FILE = YES`，所以用「部分 plist 合并」：
`Config/Info.plist` 只写自动生成覆盖不到的键，再设 `INFOPLIST_FILE = Config/Info.plist`，
Xcode 会把两边合并（`CFBundleDisplayName`、`UILaunchScreen` 等自动键都保留）。

**拖拽进度条要防"打架"**：`ProgressBar` 的 binding 写入转成 `seek(to:)`，
同时把 `isSeeking` 置位 —— 否则播放器的进度回调会不停覆盖手指位置，滑块会往回跳。

**音轨是脚本合成的**：`.tools/make_audio.py` 生成 8 首环境音乐（自然小调，
i–VI–III–VII 和弦进行，铺底 + 低音脉冲 + 空气感），用 `afconvert` 转 AAC 64kbps。
**自己合成的原因是版权** —— 完全由脚本生成，可以随仓库分发。

> 启动时**不自动播**，只预装载。一打开 App 就出声太粗暴。
> ⚠️ **`-autoplay` / `-query` 两个调试开关已移除。** 它们会让「一进页面就自动搜索/播放」，
> 看起来完全像 bug。截图验证也不能靠改变 App 的默认行为 —— 那验证的就不是真实流程了。

**播放控制的行为约定：**

| 操作 | 行为 |
|---|---|
| 上一曲 | 播过 3 秒 → 回本曲开头；否则切上一首；**已是第一首则不动并弹提示** |
| 下一曲 | 顺序模式循环；**随机模式随机取一首（不重复当前）** |
| 随机播放 | 走一条 `history` 栈，「上一曲」按历史回退而不是按队列序号 |
| 循环模式 | `.off` 播到最后一首停；`.all` 回到第一首；`.one` 单曲重播 |
| 音量 | 走系统音量键 —— iOS 惯例，Apple Music 也没有应用内滑块，故不设 `volume` 属性 |

**锁屏封面**取曲目封面（`UIImage(named: artworkName)`），不是 App 图标。

### 三种音源

| 音源 | 需要准备什么 | 说明 |
|---|---|---|
| **打包音轨** | 无 | 8 首合成环境音乐，`.tools/make_audio.py` 生成 |
| **网络电台** | 无 | 15 个公开直播流，打开即听 |
| **网易云** | 自建 API 服务 | 搜索 + 流播，见下方 |

`SongSource` 把三者统一起来，`PlayerModel` 只认 `Song.source`：

```swift
enum SongSource {
    case bundled              // 打包 m4a
    case stream(URL)          // 电台直播流
    case netease(id: Int)     // 播放时才解析地址
}
```

#### 网络电台（推荐，零配置）

电台列表取自 [88lin/lofi-radio-web](https://github.com/88lin/lofi-radio-web)（MIT），
只保留能直连的 mp3 流并逐个实测过连通性 —— bilibili 直播间需要额外解析，已剔除。

**直播流没有时长、不能拖进度**：`duration` 记为 0，`Song.isLive` 据此判断，
正在播放页换成「● 直播中」标签而不是进度条，锁屏按 `MPNowPlayingInfoPropertyIsLiveStream` 处理。

#### 网易云（需要自建服务）

```bash
git clone https://github.com/88lin/api-enhanced
cd api-enhanced && npm install && node app.js     # 默认 3000 端口
```

然后把 `NeteaseAPI.baseURL` 指过去（默认 `http://localhost:3456`，也可用 `-ncm <url>` 覆盖）。

**几个绕不开的坑：**

1. **老版 NeteaseCloudMusicApi 已经不能用了。** Binaryify 的仓库 2024 年停更，
   网易改了协议（xeapi），老版本 `/song/url` 拿不到地址。必须用 Enhanced 分支。
2. **地址是 `http://` 的。** iOS 的 ATS 默认拦明文 HTTP，所以客户端统一把
   `http://` 换成 `https://` —— 实测同一路径 https 可用（206），这样就不用给
   `music.126.net` 开例外。
3. **不要提前取地址。** 搜索结果一次 20 条，全取就是 20 个请求。
   `loadCurrent` 在真正播放时才调 `/song/url/v1`，并校验「解析期间用户有没有切歌」。
4. **localhost 需要 `NSAllowsLocalNetworking`。** 只开这一项，公网仍强制 HTTPS。

> ⚠️ **合规提醒**：这是非官方接口，仅供个人学习。曲库版权归网易云所有，
> 拿它做上架应用会被审核拒绝，也不符合网易云的服务条款。
> 要上线只能用「打包音轨 + 公开电台」这两条合法路径。

### 歌单数据

歌单曲目来自 **`PlaylistStore`**：启动时按关键词从网易云拉真实的 30 首；
拉不到就退回本地选曲（`songIDs`）。**数量跟着真实内容走，不写死。**

| 歌单 | 来源 |
|---|---|
| 每日推荐 | `/personalized/newsong`（新歌速递） |
| 民谣 / 抖音热曲 / 飙升榜 / 华语新声 / 电子浪潮 | `/search?keywords=` 各取 30 条 |

> 为什么「每日推荐」不用搜索：搜关键词是搜不出"推荐"的，只会返回名字里带这个词的歌。
>
> **封面要单独补**：`/search` 只给 `picId` 不给地址，`/song/detail?ids=` 才有 `al.picUrl`。
> 一次批量传 30 个 id，不要逐条请求。拿到后把 URL 直接塞进 `Song.artworkName`，
> `ArtworkView` 认得 `http` 开头的名字，走 `AsyncImage`。

**历史坑（已修）：** `Playlist.count` 曾是写死的 30/60/100…，而 `songIDs` 全是整库 8 首；
更隐蔽的是 `PlaylistDetailView` 里 `songs` 直接返回 `MusicLibrary.songs` ——
**歌单的 `songIDs` 完全没被用上**，点进任何歌单都是整库 8 首、按库顺序。
于是出现「30 首 · 31 分钟」这种自相矛盾的显示。

`dailyPick(count:salt:)` 仍保留，作为**本地兜底**的选曲：按「年内第几天」做种子的确定性洗牌，
同一天固定、隔天换批，对得上「每天 6:00 更新」。不能用 `shuffle()`（每次启动都变）。

> ⚠️ 远程曲库依赖自建的 API 服务。服务没起时会静默退回本地选曲，
> 歌单变成 4–8 首 —— 数字仍然是真实的，只是内容少。

### 歌词

本地音轨的歌词写在 `Song.lyrics` 里；**网易云曲目在播放时才拉**，拉不到就保持「纯音乐 · 暂无歌词」。

```
/lyric?id=  →  LRC 文本  →  NeteaseAPI.parseLRC  →  [LyricLine]
```

`parseLRC` 的几个要点：

- 只认 `[mm:ss.xx]` 这种**数字**时间戳，`[ti:]` / `[ar:]` / `[by:]` 会被正则自然跳过
- 一行可能有**多个**时间戳（`[00:12.34][01:20.56]副歌`），每个都要展开成独立的一行
- 毫秒位可能是 2 位（厘秒）或 3 位，按位数算除数：`raw / 10^位数`
- 解析完按 `time` 排序

拉回来的歌词通过 `applyLyrics(_:for:)` 写回 `queue[index]` —— **按 song id 找而不是按下标**，
因为请求往返期间队列可能已经被换过。所以 `Song.lyrics` 是 `var`。

> 网易云的 LRC 开头几行通常是「作词 / 作曲 / 制作 / 编曲」的署名，
> 时间戳在 0–3 秒。**没有过滤掉** —— 那正好是前奏的空白段，显示制作信息比空着好。

`LyricsPane` 的高亮只改**字体和透明度**（`onDark` 全亮 + 加粗 vs 42% 透明），
不加背景块。滚动用 `ScrollViewReader` + `scrollTo(anchor: .center)` 跟随当前行。

### 点歌行为

在歌单里点任意一行：**开始播放 + 自动打开「正在播放」全屏页**。

播放页用 `PlaylistDetailView` **自己的** `fullScreenCover`，不是复用根视图那个 ——
歌单是 sheet，根视图的 cover 在 sheet 之上弹不出来。
这样关闭播放页会回到歌单，而不是一路退回首页。

点「播放 / 随机播放」按钮只开始播放，不跳页 —— 那两个是"整单开始"的动作。

**进入歌单页本身不播放、也不改变当前曲目** —— 页面只是展示。
（之前有个 `-autoplay` 的截图钩子会在 `onAppear` 自动点第一行，导致一进页面就播，
已移除。自动化验证现在只打开页面，不触发播放。）

### 播放队列

`PlayerModel.upNext` = **当前曲目之后的所有曲目**。

> 之前是 `(1...min(5, count-1)).map { queue[(currentIndex+offset) % count] }` ——
> 两个问题：**只给 5 首**（30 首的歌单永远看不到剩下的），
> 而且 `% count` 会**绕回开头**（播到倒数第二首，"接下来播放"却出现第 1、2 首）。

`next()` 也不再 `% count` 绕回第一首，改成到末尾就停，返回 `Bool`。
和 `previous()` 对称：第一首点上一曲、最后一首点下一曲，都弹提示而不是循环。

### 纵向节奏

| 层级 | 值 |
|---|---|
| 区块之间 | `Spacing.section` = **20** |
| 区块标题 → 内容 | `Spacing.sm` = 12 |
| 卡片内元素之间 | `Spacing.xs` = 8 |

首页最初用 `xl`（28）做段间距，大标题和胶囊并成一行后整页显得松散，收到 20。
调这个值只改 `LiquidTheme.Spacing.section` 一处。

### 货架尺寸

| 货架 | 规格 |
|---|---|
| 最近播放 | 横向轮播，卡片 **130×130** |
| 为你推荐 | **三列**网格，6 个歌单铺满两行，卡片 ~113×113 |
| 新发行 | 横向轮播，卡片 128×128 |

两块货架的标题字号统一用 `.subheadline` + medium —— 之前最近播放用 `.headline`、
为你推荐用 `.subheadline`，并排看会一大一小。

---

## 三、界面清单

| # | 界面 | 说明 |
|---|---|---|
| 1 | 现在就听 | 大标题 + 最近播放货架 + 为你推荐 + 新发行 + 热门单曲 |
| 2 | 音乐库 | 分段控件（歌曲 / 专辑 / 艺人）+ 三种视图共用同一套底与头部 |
| 3 | 搜索 | 玻璃搜索框 + 最近搜索 chip（自写 `FlowLayout`）+ 分类网格 + 结果列表 |
| 4 | 我的 | 账户卡 + 统计 + 播放设置 + 账户设置 |
| 5 | 播放列表详情 | 大封面随滚动收合（缩放 + 淡出），标题在头部淡入 |
| 6 | 正在播放 | 重模糊封面背景 + 玻璃传输控制；点封面切歌词模式 |
| 7 | 播放队列 | 深色沉浸浮层，沿用封面氛围 |

### 真实产品内容

`Models/MusicLibrary.swift` 是一份完整曲库，不是占位数据：

- **8 首曲目**：歌名 / 艺人 / 专辑 / 时长 / 发行年 / 播放量 / 音质 / 喜欢状态
- **8 张专辑**、**8 位艺人**（含流派与月听众）
- **6 个编辑部歌单**（渐变封面 + 符号，真实产品里就是这么生成的）
- **4 首带逐行时间戳歌词**，其余标注「纯音乐 · 暂无歌词」
- 首页分组：最近播放 / 为你推荐 / 新发行 / 热门单曲，均由曲库派生

封面与头像已本地化进 Assets，运行时不联网。

---

## 四、文件结构

```
GlassMusicPlayer/
├── Theme/
│   ├── LiquidTheme.swift      令牌：语义色 / 同心圆角 / 间距 / 字体 / 动效 / 触控尺寸
│   └── LiquidGlass.swift      liquidGlass 修饰器、glassPanel、ArtworkBackdrop、SoftCanvas
├── Models/
│   └── MusicLibrary.swift     Song/Album/Playlist/Artist + 真实曲库 + PlayerModel
└── Views/
    ├── Components.swift       封面、玻璃按钮、筛选片、歌曲行、悬浮头部、进度条、迷你条、Tab Bar
    ├── RootView.swift         根容器 + 启动参数
    ├── HomeView.swift
    ├── LibraryView.swift
    ├── SearchView.swift       含自写 FlowLayout
    ├── ProfileView.swift
    ├── PlaylistDetailView.swift
    ├── NowPlayingView.swift   含 LyricsPane
    └── QueueView.swift
```

状态用 `@Observable PlayerModel` 通过 `.environment` 注入，不用一层层传 Binding。

---

## 五、踩过的坑

| 现象 | 根因 | 解法 |
|---|---|---|
| **整页布局塌陷**，标题和两侧控件全被顶出屏幕 | `Image().resizable().scaledToFill()` 直接当背景，按短边撑满，布局宽度被撑到屏幕外 | 图片挂到 `Color` 的 `.overlay` 上，由 `Color` 决定布局尺寸 |
| 屏幕底部漏出一条下层内容 | `ignoresSafeArea()` 之后加 `.clipped()`，按安全区尺寸裁 | 背景不要 `clipped()`；overlay 不影响布局，不会溢出 |
| 头部是一条**空胶囊** | 固定全宽 + 标题淡入 | 胶囊贴合内容宽度，标题出现时向左生长 |
| chrome 上文字被底下内容干扰 | 材质太透 | `.tint(chromeTint)` + `.scrollEdgeEffectStyle(.soft, for: .bottom)` |
| 迷你条和 Tab Bar 粘成一坨 | `GlassEffectContainer(spacing:)` 会改元素间距 | 不用容器，直接 `VStack(spacing: 12)` |
| **整个 App 变深色** | `fullScreenCover` 里 `NowPlayingView` 的 `.preferredColorScheme(.dark)` 会向上泄漏 | 根部显式 `.preferredColorScheme(.light)` |
| 胶囊里的图标发虚 | 按钮自带玻璃底，套在玻璃胶囊里 = 玻璃叠玻璃 | 头部内用 `HeaderIconButton`（无玻璃底） |
| Tab Bar 悬在内容中间、下方漏一条彩色内容 | iOS 26 底部工具栏按安全区约束不会贴到屏幕边缘 | `.ignoresSafeArea(.container, edges: .bottom)` + 16pt 留白 |
| **chrome 变成一块白板，没有玻璃感** | ① `chromeTint` 给到 0.62；② chrome 下面铺了 170pt 渐隐把内容洗白 | tint 降到 0.42，**删掉整片渐隐**，让玻璃重新"有东西可透" |
| 玻璃压在白色卡片上就看不见边界 | 浅色背景上白色材质与背景同色 | `glassEdge` 补一道 0.5pt 细亮边 |

---

## 六、调试参数

`#if DEBUG` 保护，仅用于截图 / UI 自动化：

```bash
xcrun simctl launch booted com.example.GlassMusicPlayer -tab 1        # 0 首页 / 1 音乐库 / 2 搜索 / 3 我的
xcrun simctl launch booted com.example.GlassMusicPlayer -nowPlaying 1 # 打开正在播放
xcrun simctl launch booted com.example.GlassMusicPlayer -tab 0 -playlist 2
xcrun simctl launch booted com.example.GlassMusicPlayer -nowPlaying 1 -queue 1
xcrun simctl launch booted com.example.GlassMusicPlayer -tab 0 -scrollBottom 1   # 以滚到底启动，看头部展开态
```

---

## 七、可访问性

- **减弱动态效果**：`accessibilityReduceMotion` 关闭所有过渡动画、跳动条与封面缩放
- **动态字体**：全部 `Font.TextStyle`，随系统字号缩放
- **触控尺寸**：所有可点元素 ≥ 44pt（`LiquidTheme.Hit`）
- **选中态**：Tab 用「一块大玻璃块 + 强调色文字」，分段控件用「实心强调色块 + 反白文字」，
  两者都带 `.isSelected` 无障碍标记

### Tab Bar 选中态

选中项背后是一块 `cornerRadius 24` 的大玻璃块，盖住图标和文字整块，跟随切换移动
（`matchedGeometryEffect`）。

**这块必须靠「色相」而不是「亮度」来区分。** 试过三轮：

| 方案 | 结果 |
|---|---|
| `accent.opacity(0.12)` 小胶囊 | 玻璃感出不来 |
| 纯白 `white.opacity(0.80)` | **完全看不见** —— Tab Bar 被 `chromeTint` 加成接近白色 |
| 极淡靛蓝 `#EEF0FF` | 薰衣草底上勉强可见，遇到**白色卡片**（我的 / 音乐库）又消失 |
| **`accent.opacity(0.20)` + 白色顶部高光 + 白→强调色渐变描边 + 强调色阴影** | 白底、薰衣草底上都清楚 |

> 根本原因：Tab Bar 的玻璃会**自适应背景**。背后是白色卡片时它自己也变白，
> 任何"比白更白"的高亮都会失效。只有染色才稳。

---

## 八、已知边界

- 当前锁定**浅色外观**。深色外观下语义色会自动反相，但玻璃的 tint 与压暗层级需要单独调一遍才能达标。
- 播放是**静态演示**：进度不会自动走，切歌不发声。
