import SwiftUI
import WidgetKit

/// 扩展入口。这个 target 只承载实时活动，没有主屏小组件。
@main
struct GlassMusicPlayerLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        PlaybackLiveActivity()
    }
}
