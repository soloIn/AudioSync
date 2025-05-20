import CoreAudio
import ScriptingBridge
import AppKit

struct TrackInfo {
    let name: String
    let artist: String
    let albumArtist: String
    let trackID: String
    let album: String
    let state: String
    let genre: String
    let color: NSColor?
    let albumCover: NSImage?
}

class PlaybackNotifier {
    var onPlay: ((TrackInfo) -> Void)?
    
    var appleMusicScript: MusicApplication? = SBApplication(
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

    @objc private func receivedPlaybackNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo else {
            return
        }
        
        guard let name = userInfo["Name"] as? String,
              let state = userInfo["Player State"] as? String else {
            return
        }
        guard let currentTrack = appleMusicScript?.currentTrack else {
            print("appleMusicScript currentTrack failed")
            return
        }
        guard let persistentID = currentTrack.persistentID else {
            print("appleMusicScript persistentID failed")
            return
        }
        guard let color =  (currentTrack.artworks?().firstObject as? MusicArtwork)?.data else {
            print("appleMusicScript color failed")
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
            color: color.findDominantColor(),
            albumCover: color
        )

        print("appleNotification：\(trackInfo)")
        onPlay?(trackInfo)
    }
    
    func scriptNotification(){
        guard let track = fetchCurrentTrack() else{
            return
        }
        
        print("scriptNotification: \(track)")
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
    func fetchCurrentTrack() -> TrackInfo?{
        guard let trackInfo = appleMusicScript?.currentTrack else {
            print("appleMusicScript currentTrack failed")
            return nil
        }
        guard let state = appleMusicScript?.playerState  else {
            print("appleMusicScript playerState failed")
            return nil
        }
        guard let color =  (trackInfo.artworks?().firstObject as? MusicArtwork)?.data else {
            print("appleMusicScript color failed")
            return nil
        }
        let track = TrackInfo(name: trackInfo.name ?? "", artist: trackInfo.artist ?? "", albumArtist: trackInfo.albumArtist ?? "", trackID: trackInfo.persistentID ?? "", album: trackInfo.album ?? "", state: stringFromPlayerState(state), genre: trackInfo.genre ?? "", color: color.findDominantColor(), albumCover: color)
        return track
    }
}

