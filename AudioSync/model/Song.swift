import SwiftData
import Foundation

@Model
final class Song {
    @Attribute(.unique) var id: String
    var trackName: String
    var lyricsData: Data?

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

    init(id: String, trackName: String, lyrics: [LyricLine]) {
        self.id = id
        self.trackName = trackName
        self.lyricsData = try? JSONEncoder().encode(lyrics)
    }

    func setLyrics(_ lines: [LyricLine]) {
        lyrics = lines
    }

    func getLyrics() -> [LyricLine] {
        lyrics
    }
}
