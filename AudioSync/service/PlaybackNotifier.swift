import AppKit
import CoreAudio
import ScriptingBridge
import SwiftUI

struct TrackInfo: Encodable, Equatable {
    let name: String
    let artist: String
    let albumArtist: String
    let trackID: String
    let album: String
    let state: PlayState
    let genre: String
    let color: [Color]?
    let albumCover: NSImage?
    enum CodingKeys: String, CodingKey {
        case name, artist, albumArtist, trackID, album, state, genre
    }
    static func == (lhs: TrackInfo, rhs: TrackInfo) -> Bool {
        return lhs.trackID == rhs.trackID
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(artist, forKey: .artist)
        try container.encode(albumArtist, forKey: .albumArtist)
        try container.encode(trackID, forKey: .trackID)
        try container.encode(album, forKey: .album)
        try container.encode(state, forKey: .state)
        try container.encode(genre, forKey: .genre)
    }
}
enum PlayState: String, Encodable {
    case playing
    case stop
}
enum PlaybackTrigger {
    case formatSwitch
    case lyrics
}
@MainActor
class PlaybackNotifier {
    var onPlay: ((TrackInfo?, PlaybackTrigger) async -> Void)?

    private lazy var appleMusicScript: MusicApplication? = SBApplication(
        bundleIdentifier: "com.apple.Music"
    )
    var viewModel: ViewModel

    init(viewModel: ViewModel) {
        self.viewModel = viewModel
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(receivedPlaybackNotification(_:)),
            name: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func receivedPlaybackNotification(
        _ notification: Notification
    ) {
        guard let userInfo = notification.userInfo,
            let state = userInfo["Player State"] as? String
        else {
            Log.backend.error(
                "appleNotification:  userInfo is missing required fields."
            )
            return
        }
        viewModel.isCurrentTrackPlaying = (state == "Playing")
        Log.backend.info("appleNotification userInfo: \(userInfo)")
        let nextAlbum = userInfo["Album"] as? String ?? ""

        if state == "Playing" && viewModel.currentAlbum != nextAlbum {
            Task {
                viewModel.currentAlbum = nextAlbum
                guard let script = self.appleMusicScript else { return }
                script.pause?()
                Log.backend.debug("pause...")
                if let onPlay = self.onPlay {
                    await onPlay(nil, .formatSwitch)  // 等待执行完
                }
                Log.backend.debug("play...")
                script.setPlayerPosition?(0.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    script.playpause?()
                }

            }
        }
        if state != "Playing" {
            viewModel.isLyricsPlaying = false
        }
        let nextName = userInfo["Name"] as? String ?? ""
        let nextArtist = userInfo["Artist"] as? String ?? ""
        let songKey = "\(nextName)-\(nextArtist)-\(nextAlbum)"
        if songKey != viewModel.currentSong {
            viewModel.currentSong = songKey
            let genre = userInfo["Genre"] as? String ?? ""
            Task {
                let trackID = try await IDFetcher.fetchTrackID(
                    name: nextName,
                    artist: nextArtist
                )
                let albumData = try await IDFetcher.fetchArtworkData(
                    name: nextName,
                    artist: nextArtist
                )

                let trackInfo = TrackInfo(
                    name: nextName,
                    artist: nextArtist,
                    albumArtist: nextAlbum,
                    trackID: String(trackID),
                    album: nextAlbum,
                    state: stringFromPlayerState(state),
                    genre: genre,
                    color: albumData.findDominantColors(),
                    albumCover: albumData
                )
                viewModel.currentTrack = trackInfo
                if let onPlay = self.onPlay {
                    await onPlay(nil, .lyrics)
                }
            }

        } else {
            Log.backend.debug("跳过重复通知: \(nextName) - \(nextArtist)")
            Task {
                if let onPlay = self.onPlay {
                    await onPlay(nil, .lyrics)
                }
            }
        }

    }

    func stringFromPlayerState(_ state: String) -> PlayState {
        switch state {
        case "Playing": return .playing
        case "Paused": return .stop
        default: return .stop
        }
    }
}
extension Dictionary where Key == AnyHashable, Value == Any {
    func uniqueKey(using fields: [String]) -> String {
        let parts = fields.map { key -> String in
            if let value = self[key] {
                return "\(key)=\(value)"
            } else {
                return "\(key)=nil"
            }
        }
        return parts.joined(separator: "|").hashValue.description
    }
}
