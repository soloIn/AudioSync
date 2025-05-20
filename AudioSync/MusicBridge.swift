import ScriptingBridge

@objc protocol iTunesApplication {
    @objc optional var currentTrack: iTunesTrack { get }
}

@objc protocol iTunesTrack {
    @objc optional var name: String { get }
    @objc optional var artist: String { get }
}

let iTunes = SBApplication(bundleIdentifier: "com.apple.Music") as? iTunesApplication
let trackName = iTunes?.currentTrack?.name
let artistName = iTunes?.currentTrack?.artist


class MusicWatcher {
    private var timer: Timer?
    private var lastTrackName: String?
    private var lastArtistName: String?

    var onTrackChanged: ((_ track: String, _ artist: String) -> Void)?

    func startWatching(interval: TimeInterval = 2.0) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    private func checkForChanges() {
        guard let currentTrack = iTunes?.currentTrack,
              let trackName = currentTrack.name,
              let artistName = currentTrack.artist else {
            return
        }

        if trackName != lastTrackName || artistName != lastArtistName {
            lastTrackName = trackName
            lastArtistName = artistName
            onTrackChanged?(trackName, artistName)
        }
    }
}
