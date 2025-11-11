//
//  SimilarArtist.swift
//  AudioSync
//
//  Created by solo on 11/6/25.
//

import SwiftUI

struct SimilarArtistView: View {
    @EnvironmentObject var viewmodel: ViewModel
    var body: some View {
        if let artist = viewmodel.currentTrack?.artist {
            HStack(spacing: 8){
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
                .frame(width: 120)
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
                        .font(.system(size: 18)) // 放大按钮图标
                        .foregroundColor(.secondary) // 与整体配色一致
                        .background(Color.clear) // 背景透明
                        .contentShape(Circle()) // 扩大点击范围但保持透明
                }
                .buttonStyle(PlainButtonStyle())
                Spacer()
            }
            .padding(5)
            .frame(width: 250)
        }
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewmodel.similarArtists) { artist in
                    Button(action: { openMusic(artist: artist.name) }) {
                        HStack(alignment: .center, spacing: 18) {
                            if !artist.url.isEmpty,
                                let url = URL(string: artist.url)
                            {
                                // 可选头像占位
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Image(systemName: "person.crop.square")
                                        .frame(width: 45, height: 45)
                                        .clipShape(
                                            RoundedRectangle(cornerRadius: 4)
                                        )
                                }
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            } else {
                                Image(systemName: "person.crop.square")
                                    .frame(width: 45, height: 45)
                                    .clipShape(
                                        RoundedRectangle(cornerRadius: 4)
                                    )
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(artist.name)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(
                                        Color(NSColor.secondaryLabelColor)
                                    )
                                    .padding()
                            }
                            .frame(width: 120, alignment: .center)

                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    Color(NSColor.windowBackgroundColor)
                                        .opacity(
                                            0.15
                                        )
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())  // 去掉默认蓝色按钮效果
                    .frame(height: 50)
                    Divider()
                }
            }
        }
        .cornerRadius(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))  // 整体背景色
        //.padding(.vertical, 16)
    }
    private func openMusic(artist: String) {
        Task {
            let artistID = try await IDFetcher.fetchArtistID(
                name: "",
                artist: artist
            )
            // 步骤 2: 使用 ID 跳转到艺术家主页 (使用 Universal Link，如 MusicNavigator 中所推荐)
            let success = try MusicNavigator.openArtistPage(
                by: String(artistID)
            )
        }
    }
}

#Preview {
    let previewViewModel: ViewModel = {
        let vm = ViewModel()
        vm.currentTrack = TrackInfo(
            name: "nextName",
            artist: "nextArtist",
            albumArtist: "nextAlbum",
            trackID: "trackID",
            album: "nextAlbum",
            state: .playing,
            genre: "genre",
            color: [],
            albumCover: nil
        )
        vm.similarArtists = [
            Artist(name: "Artist A", url: ""),
            Artist(name: "Artist B", url: ""),
            Artist( name: "Artist C", url: "")
        ]
        return vm
    }()

    SimilarArtistView()
        .environmentObject(previewViewModel)
}
