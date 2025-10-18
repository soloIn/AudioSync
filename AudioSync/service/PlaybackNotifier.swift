import AppKit
import CoreAudio
import ScriptingBridge
import SwiftUI

struct TrackInfo: Encodable {
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
    case notification
    case script
}
class PlaybackNotifier {
    var onPlay: ((TrackInfo?, PlaybackTrigger) async -> Void)?

    private lazy var appleMusicScript: MusicApplication? = SBApplication(
        bundleIdentifier: "com.apple.Music"
    )
    private var audioManager = AudioFormatManager.shared
    
    
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
            let state = userInfo["Player State"] as? String
        else {
            Log.backend.error(
                "appleNotification:  userInfo is missing required fields."
            )
            return
        }

        Log.backend.info("appleNotification userInfo: \(userInfo)")
        let albumKey = userInfo.uniqueKey(using: ["Album", "Artist"])
        let album = userInfo["Album"] as? String
        
        Task { @MainActor in
            if state == "Playing" && audioManager.lastAlbum != album
            {
                audioManager.lastAlbum = album
                //audioManager.isSameAlbum.updateValue(true, forKey: albumKey)
                let script = appleMusicScript
                script?.pause?()
                Log.backend.info("pause...")
                if let onPlay = onPlay {
                    await onPlay(nil, .notification)  // 等待执行完
                }
                Log.backend.info("play...")
                script?.setPlayerPosition?(0.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    script?.playpause?()
                }
                
//                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
//                    [weak self] in
//                    self?.audioManager.isSameSong.removeValue(
//                        forKey: songKey
//                    )
//
//                }
            }
        }
    }

    func scriptNotification() {
        guard let track = fetchCurrentTrack() else {
            return
        }

        Log.backend.info("scriptNotification track: \(JSON.stringify(track))")
        Task {
            if let onPlay = onPlay {
                await onPlay(track, .script)  // 等待执行完
            }
        }
    }
    func stringFromPlayerState(_ state: MusicEPlS) -> PlayState {
        switch state {
        case .playing: return .playing
        case .stopped: return .stop
        default: return .stop
        }
    }
    func fetchCurrentTrack() -> TrackInfo? {
        guard let script = appleMusicScript else {
            Log.backend.error("appleMusicScript: 脚本对象不存在")
            return nil
        }
        
        let trackInfo = script.currentTrack
        let persistentID = trackInfo?.persistentID
        let state = script.playerState
        let artworkData = (trackInfo?.artworks?().firstObject as? MusicArtwork)?
            .data

        // 统一检查必填字段
        let required: [(String, Any?)] = [
            ("currentTrack", trackInfo),
            ("persistentID", persistentID),
            ("playerState", state),
            ("artworkData", artworkData),
        ]

        if let missing = required.first(where: { $0.1 == nil }) {
            Log.backend.error("appleMusicScript: 缺少 \(missing.0) \n  trackInfo: \(dump(trackInfo))")
            return nil
        }

        let track = TrackInfo(
            name: trackInfo?.name ?? "",
            artist: trackInfo?.artist ?? "",
            albumArtist: trackInfo?.albumArtist ?? "",
            trackID: persistentID!,
            album: trackInfo?.album ?? "",
            state: stringFromPlayerState(state!),
            genre: trackInfo?.genre ?? "",
            color: artworkData?.findDominantColors(),
            albumCover: artworkData
        )
        return track
    }

    func fetchCurrentTrackWithRetry(
        maxRetryCount: Int = 3,
        delaySeconds: Double = 0.5
    ) async -> TrackInfo? {
        for attempt in 1...maxRetryCount {
            if let track = fetchCurrentTrack() {
                return track
            } else {
                if attempt < maxRetryCount {
                    Log.backend.error(
                        "第 \(attempt) 次尝试失败，\(delaySeconds) 秒后重试..."
                    )
                    try? await Task.sleep(
                        nanoseconds: UInt64(delaySeconds * 1_000_000_000)
                    )
                } else {
                    Log.backend.error("达到最大重试次数，放弃。")
                }
            }
        }
        return nil
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
