import AppKit
import CoreAudio
import ScriptingBridge

struct TrackInfo {
    let name: String
    let artist: String
    let albumArtist: String
    let trackID: String
    let album: String
    let state: String
    let genre: String
    let color: [NSColor]?
    let albumCover: NSImage?
}

class PlaybackNotifier {
    var onPlay: ((TrackInfo) -> Void)?

    private lazy var appleMusicScript: MusicApplication? = SBApplication(
        bundleIdentifier: "com.apple.Music")

    init() {
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
            let name = userInfo["Name"] as? String,
            let state = userInfo["Player State"] as? String
        else {
            print(
                "appleNotification:  userInfo is missing required fields.")
            return
        }

        guard let script = appleMusicScript,
            let currentTrack = script.currentTrack,  // 首先确保 currentTrack 存在
            let persistentID = currentTrack.persistentID,  // 然后安全地访问其属性
            let artworkData =
                (currentTrack.artworks?().firstObject as? MusicArtwork)?.data
        else {
            print(
                "appleMusicScript: Failed to retrieve complete track information "
            )
            return
        }
        let trackInfo = TrackInfo(
            name: name,
            artist: userInfo["Artist"] as? String ?? "",
            albumArtist: userInfo["Album Artist"] as? String ?? "",
            trackID: persistentID,
            album: userInfo["Album"] as? String ?? "",
            state: state,
            genre: userInfo["Genre"] as? String ?? "",
            color: artworkData.findDominantColors(),
            albumCover: artworkData
        )

        #if DEBUG

        print("appleNotification：\(trackInfo)")

        #endif
        onPlay?(trackInfo)
    }

    func scriptNotification() {
        guard let track = fetchCurrentTrack() else {
            return
        }

        #if DEBUG

        print("scriptNotification: \(track)")

        #endif
        onPlay?(track)
    }
    func stringFromPlayerState(_ state: MusicEPlS) -> String {
        switch state {
        case .playing: return "playing"
        case .paused: return "paused"
        case .stopped: return "stopped"
        default: return "unknown(\(state.rawValue))"
        }
    }
    func fetchCurrentTrack() -> TrackInfo? {
        guard let script = appleMusicScript,  // 确保 appleMusicScript 存在
            let trackInfo = script.currentTrack,  // 确保 currentTrack 存在
            let persistentID = trackInfo.persistentID,  // 安全访问 persistentID
            let state = script.playerState,
            let artworkData =
                (trackInfo.artworks?().firstObject as? MusicArtwork)?.data
        else {  // 安全访问 playerState
            #if DEBUG
            print("appleMusicScript: Failed to retrieve current track")
            #endif
            return nil
        }

        let track = TrackInfo(
            name: trackInfo.name ?? "", artist: trackInfo.artist ?? "",
            albumArtist: trackInfo.albumArtist ?? "",
            trackID: trackInfo.persistentID ?? "", album: trackInfo.album ?? "",
            state: stringFromPlayerState(state), genre: trackInfo.genre ?? "",
            color: artworkData.findDominantColors(), albumCover: artworkData)
        return track
    }
}
