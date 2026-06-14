// LiveAlbumWidget.swift
// 显示 Live Album 数量与待分类照片;点击深链回主 App。
// 依赖:WidgetSharedData(与主 App 共用)

import SwiftUI
import WidgetKit

struct LiveAlbumWidget: Widget {
    let kind: String = "LiveAlbumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LiveAlbumTimelineProvider()) { entry in
            LiveAlbumWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("动态相册")
        .description("查看动态相册与待分类照片数量。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LiveAlbumEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct LiveAlbumTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> LiveAlbumEntry {
        LiveAlbumEntry(date: .now, snapshot: WidgetSnapshot(
            liveAlbumCount: 3,
            totalCategories: 8,
            pendingPhotos: 24,
            lastUpdated: .now,
            liveAlbumSummaries: []
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (LiveAlbumEntry) -> Void) {
        let snapshot = WidgetSharedData.readSnapshot()
        completion(LiveAlbumEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LiveAlbumEntry>) -> Void) {
        let snapshot = WidgetSharedData.readSnapshot()
        let entry = LiveAlbumEntry(date: .now, snapshot: snapshot)
        // 1 小时后下次刷新,避免 widget 进程被频繁唤醒
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct LiveAlbumWidgetView: View {
    let entry: LiveAlbumEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallBody
        case .systemMedium:
            mediumBody
        default:
            smallBody
        }
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.tint)
                Text("Smart Album")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(entry.snapshot.liveAlbumCount)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
            Text("动态相册")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Divider()
            HStack {
                Image(systemName: "tray")
                Text("\(entry.snapshot.pendingPhotos) 待分类")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .widgetURL(URL(string: "smartalbum://home"))
    }

    private var mediumBody: some View {
        HStack(alignment: .top, spacing: 16) {
            smallBody
                .frame(maxWidth: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("动态相册")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if entry.snapshot.liveAlbumSummaries.isEmpty {
                    Text("尚未创建动态相册")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(entry.snapshot.liveAlbumSummaries.prefix(3), id: \.categoryId) { summary in
                        HStack {
                            Image(systemName: "rectangle.stack")
                                .font(.caption2)
                            Text(summary.name)
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer()
                            Text("\(summary.matchCount)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .widgetURL(URL(string: "smartalbum://live-albums"))
    }
}
