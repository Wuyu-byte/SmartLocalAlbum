// SmartAlbumWidgetBundle.swift
// SmartAlbumWidget Extension 入口;独立 target 编译,需在 Xcode 中手动添加。
// App Group: group.com.loyuk.SmartLocalAlbum

import SwiftUI
import WidgetKit

@main
struct SmartAlbumWidgetBundle: WidgetBundle {
    var body: some Widget {
        LiveAlbumWidget()
    }
}
