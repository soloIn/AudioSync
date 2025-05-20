//
//  KaraokeView.swift
//  AudioSync
//
//  Created by solo on 5/12/25.
//

import SwiftUI

struct KaraokeView: View {
    
    
    struct VisualEffectView: NSViewRepresentable {
        func makeNSView(context: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView()

            view.blendingMode = .behindWindow
            view.state = .active
            view.material = .hudWindow

            return view
        }

        func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
            
            nsView.material = .hudWindow
            nsView.blendingMode = .behindWindow
        }
    }
    
    @EnvironmentObject var viewmodel: ViewModel
    func multilingualView(_ currentlyPlayingLyricsIndex: Int) -> some View {
        VStack(spacing: 6) {
            Text(verbatim: viewmodel.currentlyPlayingLyrics[currentlyPlayingLyricsIndex].words)
            if let trlycs = viewmodel.currentlyPlayingLyrics[currentlyPlayingLyricsIndex].attachments[.translation()]?.stringValue, !trlycs.isEmpty{
                Text(verbatim: trlycs)
                    .font(.custom(viewmodel.karaokeFont.fontName, size: 0.9*(viewmodel.karaokeFont.pointSize)))
                    .opacity(0.85)
            }
        }
    }
    
    @ViewBuilder func lyricsView() -> some View {
        if let currentlyPlayingLyricsIndex = viewmodel.currentlyPlayingLyricsIndex {
            if viewmodel.translationExists {
                if viewmodel.karaokeShowMultilingual {
                    multilingualView(currentlyPlayingLyricsIndex)
                }
                else {
                    Text(verbatim: viewmodel.currentlyPlayingLyrics[currentlyPlayingLyricsIndex].words)
                }
            } else {
                if let toLatin = viewmodel.currentlyPlayingLyrics[currentlyPlayingLyricsIndex].words.applyingTransform(.toLatin, reverse: false) {
                    Text(verbatim: toLatin)
                } else {
                    Text(verbatim: viewmodel.currentlyPlayingLyrics[currentlyPlayingLyricsIndex].words)
                }
            }
        } else {
            Text("")
        }
    }
    var body: some View {
        lyricsView()
            .lineLimit(2)
            .foregroundStyle(.white)
            .minimumScaleFactor(0.9)
            .font(.custom(viewmodel.karaokeFont.fontName, size: viewmodel.karaokeFont.pointSize))
            .padding(10)
            .padding(.horizontal, 10)
            .background {
                Group {
                    if  let currentBackground = viewmodel.currentAlbumColor {
                        Color(currentBackground.balancedColor)
                    }                }
                .transition(.opacity)
                .opacity(0.8)
            }
            .drawingGroup()
            .background(
                VisualEffectView().ignoresSafeArea()
            )
            .cornerRadius(16)
            .multilineTextAlignment(.center)
            .frame(minWidth: 800, maxWidth: 800, minHeight: 100, maxHeight: 100, alignment: .center)

    }}

//#Preview {
//    KaraokeView()
//        .environmentObject(ViewModel.preview)
//}
