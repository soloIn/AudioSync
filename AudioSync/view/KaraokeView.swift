//
//  KaraokeView.swift
//  AudioSync
//
//  Created by solo on 5/12/25.
//

import SwiftUI

struct KaraokeView: View {

    @EnvironmentObject var viewmodel: ViewModel
    func multilingualView(_ currentlyPlayingLyricsIndex: Int) -> some View {
        VStack(spacing: 6) {
            Text(
                verbatim: viewmodel.currentlyPlayingLyrics[
                    currentlyPlayingLyricsIndex
                ].words
            )
            if let trlycs = viewmodel.currentlyPlayingLyrics[
                currentlyPlayingLyricsIndex
            ].attachments[.translation()]?.stringValue, !trlycs.isEmpty {
                Text(verbatim: trlycs)
                    .font(
                        .custom(
                            viewmodel.karaokeFont.fontName,
                            size: 0.9 * (viewmodel.karaokeFont.pointSize)
                        )
                    )
                //                    .opacity(0.85)
            }
        }
    }

    @ViewBuilder func lyricsView() -> some View {
        if let currentlyPlayingLyricsIndex = viewmodel
            .currentlyPlayingLyricsIndex,
            viewmodel.currentlyPlayingLyrics.indices.contains(
                currentlyPlayingLyricsIndex
            ),
            !viewmodel.currentlyPlayingLyrics[currentlyPlayingLyricsIndex].words
                .isEmpty
        {
            multilingualView(currentlyPlayingLyricsIndex)
        } else {
            Text("···")
        }
    }
    var body: some View {
        lyricsView()
            .lineLimit(2)
            .foregroundStyle(.white)
            .minimumScaleFactor(0.9)
            .font(
                .custom(
                    viewmodel.karaokeFont.fontName,
                    size: viewmodel.karaokeFont.pointSize
                )
            )
            .padding(10)
            .padding(.horizontal, 10)
            .background {
                VisualEffectView().ignoresSafeArea()
                if let colors = viewmodel.currentTrack?.color {
                    if !colors.isEmpty {
                        ZStack {
                            LinearGradient(
                                gradient: Gradient(
                                    colors: colors
                                ),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Color.black.opacity(0.1)
                        }
                    }
                }

            }
            .cornerRadius(16)
            .multilineTextAlignment(.center)
            .frame(
                minWidth: 800,
                maxWidth: 800,
                minHeight: 100,
                maxHeight: 100,
                alignment: .center
            )

    }
}
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()

        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .popover

        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {

        nsView.material = .popover
        nsView.blendingMode = .behindWindow
    }
}
//#Preview {
//    KaraokeView()
//        .environmentObject(ViewModel.preview)
//}
