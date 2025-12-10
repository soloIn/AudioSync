import AppKit
import Foundation
import SwiftData

struct Artist: Identifiable, Sendable, Encodable {
    var id: String
    var mbid: String
    var name: String
    var url: String
    var image: Data?

    init(name: String, url: String = "", mbid: String = "") {
        self.id = "artist:\(name)+\(url)"
        self.name = name
        self.url = url
        self.mbid = mbid
    }

}
struct ArtistFromLastFMResponse: Decodable, Encodable {
    let similarartists: Similarartists?

    struct Similarartists: Decodable, Encodable {
        let artist: [ArtistEntity]?

        struct ArtistEntity: Decodable, Encodable {
            let name: String
            let mbid: String?
            let url: String
        }
    }
}

struct SimilarSong: Identifiable, Sendable, Encodable {
    var id: String
    var name: String
    var mbid: String
    var artist: String
    init(name: String, mbid: String, artist: String = "") {
        self.id = "song:\(name)-\(artist)"
        self.name = name
        self.mbid = mbid
        self.artist = artist
    }

}
struct SongFromLastFMResponse: Decodable, Encodable {
    let similartracks: SongFromLastFMResponse.SimilarTrack?

    struct SimilarTrack: Decodable, Encodable {
        let track: [SimilarTrack.TrackEntity]
        struct TrackEntity: Decodable, Encodable {
            let name: String
            let mbid: String?
            let artist: TrackEntity.Artist
            struct Artist: Decodable, Encodable {
                let name: String
            }
        }
    }
}
