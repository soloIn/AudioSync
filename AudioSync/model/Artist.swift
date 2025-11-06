
import SwiftData
import Foundation
@Model
class Artist {
    @Attribute(.unique) var id: String
    var mbid: String
    var name: String
    var url: String
    
    init(name: String, url: String = "", mbid: String = "") {
        self.id = UUID().uuidString
        self.name = name
        self.url = url
        self.mbid = mbid
    }
    
}
struct ArtistResponse: Decodable, Encodable{
    let similarartists: Similarartists?
    
    struct Similarartists: Decodable, Encodable {
        let artist: [ArtistEntity]?
        
        struct ArtistEntity: Decodable , Encodable{
            let name: String
            let mbid: String?
            let url: String
        }
    }
}
