//
//  SimilarArtist.swift
//  AudioSync
//
//  Created by solo on 11/6/25.
//

import SwiftUI

struct HoverTextCard: View {
    let text: String

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
                .multilineTextAlignment(.leading)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SimilarArtistRowView: View {
    let artist: ArtistFromLastFM

    var body: some View {
        Button(action: {
            openMusic(artist: artist.name)
        }) {
            HStack(alignment: .center, spacing: 18) {
                artistImage
                artistInfo
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.15))
            )
        }
        .contentShape(Rectangle())
        .buttonStyle(PlainButtonStyle())
        .frame(height: 120)
    }

    private var artistImage: some View {
        Group {
            if let image = artist.image,
                let nsImage = NSImage(data: image)
            {
                Image(nsImage: nsImage)
                    .resizable()
            } else {
                Image(systemName: "person.crop.square")
            }
        }
        .frame(width: 116, height: 116)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var artistInfo: some View {
        VStack {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(artist.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
            }
            .frame(height: 25, alignment: .leading)

            if let content = artist.content {
                HoverableContentView(
                    content: content
                )
            }
        }
    }

    private func openMusic(artist: String) {
        Task {
            let artistID = try await IDFetcher.fetchArtistID(
                name: "",
                artist: artist,
                album: ""
            )
            // 步骤 2: 使用 ID 跳转到艺术家主页 (使用 Universal Link，如 MusicNavigator 中所推荐)
            _ = try MusicNavigator.openArtistPage(
                by: String(artistID)
            )
        }
    }
}
struct HoverableContentView: View {
    let content: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(content)
                .font(.system(size: 13))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .systemTooltip(content.toSimplified)
        }
    }
}

struct SimilarArtistView: View {
    @EnvironmentObject var viewmodel: ViewModel
    var body: some View {
        if let artist = viewmodel.currentTrack?.artist {
            HStack(spacing: 8) {
                Spacer()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        Text("\(artist)")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(NSColor.secondaryLabelColor))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .frame(minWidth: 120)
                }
                .frame(width: 180)
                Text(" 相似歌手")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(
                        Color(NSColor.secondaryLabelColor)
                    )
                    .frame(width: 70)
                Button(action: {
                    withAnimation {
                        viewmodel.refreshSimilarArtist = true
                    }
                }) {
                    Image(systemName: "arrow.clockwise.circle")
                        .font(.system(size: 18))  // 放大按钮图标
                        .foregroundColor(.secondary)  // 与整体配色一致
                        .background(Color.clear)  // 背景透明
                        .contentShape(Circle())  // 扩大点击范围但保持透明
                }
                .buttonStyle(PlainButtonStyle())
                Spacer()
            }
            .padding(5)
            .frame(width: 300)
        }
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(
                    Array(viewmodel.similarArtists.enumerated()),
                    id: \.offset
                ) { index, artist in
                    SimilarArtistRowView(
                        artist: artist
                    )
                    .environmentObject(viewmodel)
                    Divider()
                }
            }
        }
        .cornerRadius(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))  // 整体背景色
    }
}
