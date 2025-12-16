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
    var color: [Color]?
    var albumCover: Data?
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
    case paused
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

    private var lastNotificationKey: String?
    var lock: Bool = false

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
            Log.notice.notice(
                "trackInfo is missing",
                "apple music distributedNotification"
            )
            return
        }
        let playState = playerStateFromNotifier(state)
        let uniqueKey = userInfo.uniqueKey(using: [
            "Name", "Artist", "Album", "Player State",
        ])
        if uniqueKey == lastNotificationKey {
            return
        }
        lastNotificationKey = uniqueKey

        let songKey = userInfo.uniqueKey(using: [
            "Name", "Artist", "Album",
        ])

        viewModel.isCurrentTrackPlaying = (playState == PlayState.playing)
        Log.backend.info("appleNotification userInfo: \(userInfo)")
        let nextAlbum = userInfo["Album"] as? String ?? ""
        let nextName = userInfo["Name"] as? String ?? ""
        if !lock && playState == PlayState.playing && !nextAlbum.isEmpty
            && viewModel.currentAlbum != nextAlbum && viewModel.enableAudioSync
        {
            lock = true
            Task {
                defer { lock = false }
                viewModel.currentAlbum = nextAlbum
                guard let script = self.appleMusicScript else { return }
                script.playpause?()
                Log.backend.info("pause \(nextName) ⏹️")
                if let onPlay = self.onPlay {
                    await onPlay(nil, .formatSwitch)  // 等待执行完
                }

                script.setPlayerPosition?(0.0)
                await waitUntilPaused(script)
                script.playpause?()
                Log.backend.info("play \(nextName) ✅")

            }
        }
        if playState != PlayState.playing {
            viewModel.isLyricsPlaying = false
        }
        let nextArtist = userInfo["Artist"] as? String ?? ""
        if songKey != viewModel.currentSongKey {
            viewModel.currentSongKey = songKey
            let genre = userInfo["Genre"] as? String ?? ""
            Task {
                let trackID = try await IDFetcher.fetchTrackID(
                    name: nextName,
                    artist: nextArtist,
                    album: nextAlbum
                )
                let albumData = try await IDFetcher.fetchArtworkData(
                    name: nextName,
                    artist: nextArtist,
                    album: nextAlbum
                )

                let trackInfo = TrackInfo(
                    name: nextName,
                    artist: nextArtist,
                    albumArtist: nextAlbum,
                    trackID: String(trackID),
                    album: nextAlbum,
                    state: playState,
                    genre: genre,
                    color: NSImage(data: albumData)?.findDominantColors(),
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

    func playerStateFromNotifier(_ state: String) -> PlayState {
        switch state {
        case "Playing": return PlayState.playing
        default: return .stop
        }
    }
    func playerStateFromScript(_ state: MusicEPlS) -> PlayState {
        switch state {
        case MusicEPlS.playing: return PlayState.playing
        default: return .stop
        }
    }
    func obtainPlayback() async {
        guard let script = self.appleMusicScript else { return }
        guard let album = script.currentTrack?.album,
            let artist = script.currentTrack?.artist,
            let name = script.currentTrack?.name,
            let genre = script.currentTrack?.genre,
            let albumArtist = script.currentTrack?.albumArtist,
            let state = script.playerState
        else { return }

        guard
            let trackID = try? await IDFetcher.fetchTrackID(
                name: name,
                artist: artist,
                album: album
            ),
            let albumData = try? await IDFetcher.fetchArtworkData(
                name: name,
                artist: artist,
                album: album
            )
        else { return }
        let trackInfo = TrackInfo(
            name: name,
            artist: artist,
            albumArtist: albumArtist,
            trackID: String(trackID),
            album: album,
            state: playerStateFromScript(state),
            genre: genre,
            color: NSImage(data: albumData)?.findDominantColors(),
            albumCover: albumData
        )
        viewModel.currentTrack = trackInfo
        let keyInfo: [AnyHashable: Any] = [
            "Artist": artist,
            "Album": album,
            "Name": name,
        ]

        let songKey = keyInfo.uniqueKey(using: [
            "Name", "Artist", "Album",
        ])
        viewModel.currentSongKey = songKey
        viewModel.isCurrentTrackPlaying = (state == MusicEPlS.playing)

    }
    func waitUntilPaused(
        _ script: MusicApplication,
        timeout: Int = 50
    ) async {
        for i in 0..<timeout {
            let isPaused = await MainActor.run {
                script.playerState != .playing
            }

            if isPaused {
                Log.backend.info(
                    "waitUntilPaused active play time consuming : \(i * 80) ms"
                )
                return
            }

            try? await Task.sleep(nanoseconds: 80_000_000)
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
