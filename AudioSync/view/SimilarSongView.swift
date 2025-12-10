//
//  SimilarSongView.swift
//  AudioSync
//
//  Created by solo on 5/19/25.
//
import SwiftUI

struct SimilarSongView: View {
    @EnvironmentObject var viewModel: ViewModel

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                // 固定 currentTrack 显示
                if let trackName = viewModel.currentTrack?.name {
                    HStack(spacing: 12) {
                        // 左侧封面（圆角封面图片，支持 NSImage 转换；无图时显示默认占位图形）
                        if let albumCover = viewModel.currentTrack?.albumCover {
                            albumCover.toSwiftUIImage()
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 45, height: 45)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(NSColor.controlAccentColor))
                                .frame(width: 45, height: 45)
                        }

                        // 歌曲名 + 艺人信息
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(trackName)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color(NSColor.labelColor))

                            if let artist = viewModel.currentTrack?.artist {
                                Text(artist)
                                    .font(.system(size: 13))
                                    .foregroundColor(
                                        Color(NSColor.secondaryLabelColor)
                                    )
                            }
                        }

                        Spacer()

                        Button(action: {
                            withAnimation {
                                viewModel.needNanualSelection = false
                                viewModel.onCandidateSelected = nil
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Color.green.opacity(0.6))
                                .imageScale(.large)
                        }
                        .buttonStyle(.plain)
                        .help("取消选择")
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 5)
                    .padding(.top, 5)
                }
                // 滚动候选项
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.allCandidates, id: \.id) { song in
                            CandidateRow(song: song, viewModel: viewModel)  // 提取子视图
                                .frame(height: 42)  // 固定行高
                                .padding(.horizontal)

                            Divider()
                                .background(Color(NSColor.separatorColor))
                                .padding(.horizontal)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .frame(width: 420, height: 450)  // 固定尺寸
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.9))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            )
            .padding(20)
        }
    }

    // 提取子视图
    private struct CandidateRow: View {
        let song: CandidateSong  // 假设Song是你的数据模型
        let viewModel: ViewModel
        @State private var isHovered = false

        var body: some View {
            Button(action: selectSong) {
                HStack {
                    if !song.albumCover.isEmpty,
                        let url = URL(string: song.albumCover)
                    {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    Color(NSColor.controlAccentColor).opacity(
                                        0.3
                                    )
                                )
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(NSColor.controlAccentColor))
                            .frame(width: 40, height: 40)
                    }
                    // 水平滚动文本容器
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text("\(song.name) - \(song.artist) - \(song.album)")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(NSColor.secondaryLabelColor))
                            .padding(.horizontal, 16)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 42)
                .background(isHovered ? Color.blue.opacity(0.6) : Color.clear)  // 悬停背景
                .cornerRadius(8)
                .contentShape(Rectangle())  // 确保整个区域可点击
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
        }

        private func selectSong() {
            withAnimation {
                viewModel.needNanualSelection = false
                viewModel.onCandidateSelected?(song)
                viewModel.onCandidateSelected = nil
            }
        }
    }
}
