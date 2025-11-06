//
//  SimilarArtist.swift
//  AudioSync
//
//  Created by solo on 11/6/25.
//

import SwiftUI

struct SimilarArtistView: View {
    @EnvironmentObject var viewmodel: ViewModel
    @State private var artists: [Artist] = []
    @State private var networkUtil: NetworkUtil? = nil
    @State private var fetchTask: Task<Void, Never>?

    var body: some View {
        ScrollView{
            LazyVStack(spacing: 12){
                ForEach(artists) { artist in
                    Button(action: { openMusic(artist: artist.name) }) {
                        HStack(spacing: 12) {
                            // 可选头像占位
                            Image(systemName: "person.crop.square")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                                .foregroundColor(.accentColor)

                            Text(artist.name)
                                .font(.headline)
                                .foregroundColor(.primary)

                            Spacer()
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    Color(NSColor.windowBackgroundColor).opacity(
                                        0.15
                                    )
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())  // 去掉默认蓝色按钮效果
                    
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))  // 整体背景色
        .onAppear {
            if networkUtil == nil {
                networkUtil = NetworkUtil(viewModel: viewmodel)
            }
            fetchRequest()
        }
        .onDisappear {
            fetchTask?.cancel()
        }
    }
    private func openMusic(artist: String) {
        Task {
            let artistID = try await IDFetcher.fetchArtistID(by: artist)
            // 步骤 2: 使用 ID 跳转到艺术家主页 (使用 Universal Link，如 MusicNavigator 中所推荐)
            let success = try MusicNavigator.openArtistPage(by: artistID)
        }
    }
    private func fetchRequest() {
        fetchTask = Task {
            do {
                Log.ui.info(viewmodel.currentTrack?.artist ?? "")
                if let fetched = try await networkUtil?.fetchSimilarArtists(
                    name: viewmodel.currentTrack?.artist ?? ""
                ) {
                    DispatchQueue.main.async {
                        self.artists = fetched
                    }
                }
            } catch {

            }
        }
    }
}

#Preview {
    SimilarArtistView()
}
