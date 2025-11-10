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
        .padding(.vertical, 16)
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
    SimilarArtistView()
}
