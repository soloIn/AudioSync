import SwiftData
import Foundation

@Model
final class Song {
    @Attribute(.unique) var id: String
    var trackName: String
    var lyricsData: Data?
    @Attribute(.externalStorage) var cover: Data?

    // 自定义属性（不存储，只是映射）
    var lyrics: [LyricLine] {
        get {
            guard let data = lyricsData else { return [] }
            return (try? JSONDecoder().decode([LyricLine].self, from: data)) ?? []
        }
        set {
            lyricsData = try? JSONEncoder().encode(newValue)
        }
    }

    init(id: String, trackName: String, lyrics: [LyricLine], cover: Data) {
        self.id = id
        self.trackName = trackName
        self.lyricsData = try? JSONEncoder().encode(lyrics)
        self.cover = cover
    }

    func setLyrics(_ lines: [LyricLine]) {
        lyrics = lines
    }

    func getLyrics() -> [LyricLine] {
        lyrics
    }
}

struct CandidateSong: Sendable {
    let id: String
    let name: String
    let artist: String
    let album: String
    var albumId: String
    var albumCover: String
    let source: LyricsFormat
}
