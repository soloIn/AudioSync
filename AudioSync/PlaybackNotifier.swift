import AppKit
import CoreAudio
import ScriptingBridge
import SwiftUI
struct TrackInfo {
    let name: String
    let artist: String
    let albumArtist: String
    let trackID: String
    let album: String
    let state: PlayState
    let genre: String
    let color: [Color]?
    let albumCover: NSImage?
}
enum PlayState {
    case playing
    case stop
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
        print("appleNotification: \(userInfo)")

        Task {
            guard let scriptTrack = await fetchCurrentTrackWithRetry()
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
                trackID: scriptTrack.trackID,
                album: userInfo["Album"] as? String ?? "",
                state: state == "Playing" ? .playing : .stop,
                genre: userInfo["Genre"] as? String ?? "",
                color: scriptTrack.color,
                albumCover: scriptTrack.albumCover
            )

            #if DEBUG

            print("appleNotification：\(trackInfo)")

            #endif
            onPlay?(trackInfo)
        }
        
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
    func stringFromPlayerState(_ state: MusicEPlS) -> PlayState {
        switch state {
        case .playing: return .playing
        case .stopped: return .stop
        default: return .stop
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
            trackID: persistentID, album: trackInfo.album ?? "",
            state: stringFromPlayerState(state), genre: trackInfo.genre ?? "",
            color: artworkData.findDominantColors(), albumCover: artworkData)
        return track
    }
    func fetchCurrentTrackWithRetry(
        maxRetryCount: Int = 3,
        delaySeconds: Double = 0.5
    ) async -> TrackInfo? {
        for attempt in 1...maxRetryCount {
            if let track =  fetchCurrentTrack() {
                return track
            } else {
                if attempt < maxRetryCount {
                    print("第 \(attempt) 次尝试失败，\(delaySeconds) 秒后重试...")
                    try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                } else {
                    print("达到最大重试次数，放弃。")
                }
            }
        }
        return nil
    }
}
