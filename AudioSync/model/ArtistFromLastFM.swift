import AppKit
import Foundation
import SwiftData

struct ArtistFromLastFM: Identifiable, Sendable, Encodable {
    var id: String
    var mbid: String
    var name: String
    var sourceName: String
    var url: String
    var image: Data?
    var summary: String?
    var content: String?

    init(sourceName: String, name: String, url: String = "", mbid: String = "") {
        self.id = "artist:\(name)+\(url)"
        self.name = name
        self.sourceName = sourceName
        self.url = url
        self.mbid = mbid
    }

}
struct SimilarArtistFromLastFMResponse: Decodable, Encodable {
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
struct ArtistFromLastFMResponse: Decodable, Encodable {
    let artist: ArtistFromLastFMResponse.Artist
    struct Artist: Decodable, Encodable {
        let mbid: String?
        let name: String
        let bio: ArtistFromLastFMResponse.Artist.Bio
        struct Bio: Decodable, Encodable {
            let summary: String
            let content: String
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
