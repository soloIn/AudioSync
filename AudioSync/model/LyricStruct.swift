import Foundation


public struct LyricLine: Decodable, Hashable, Encodable, Equatable {
    public var startTimeMS: TimeInterval
    public let words: String
    public var attachments: Attachments
    public let id = UUID()

    enum CodingKeys: String, CodingKey {
        case startTimeMS = "startTimeMs"
        case words
        case attachments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            self.startTimeMS = try container.decode(
                TimeInterval.self, forKey: .startTimeMS)
        } catch {
            let str = try container.decode(String.self, forKey: .startTimeMS)
            self.startTimeMS = TimeInterval(str) ?? 0
        }
        self.words = try container.decode(String.self, forKey: .words)
        self.attachments =
            try container.decodeIfPresent(
                Attachments.self, forKey: .attachments) ?? Attachments()
    }

    init(
        startTime: TimeInterval, words: String,
        attachments: Attachments = Attachments()
    ) {
        self.startTimeMS = startTime
        self.words = words
        self.attachments = attachments
    }
}

struct NetEaseSearch: Decodable {
    let result: Result

    struct Result: Decodable {
        let songs: [Song]

        struct Song: Decodable {
            let name: String
            let id: Int
            let duration: Int?  // milliseconds
            let al: Album
            let ar: [Artist]
        }

        struct Album: Decodable {
            let id: Int
            let name: String
            let picUrl: String
        }

        struct Artist: Decodable {
            let name: String
        }
    }
}

struct NetEaseLyrics: Decodable {
    let lrc: Lyric?
    let klyric: Lyric?
    let tlyric: Lyric?
    let lyricUser: User?
    let yrc: Lyric?
    /*
    let sgc: Bool
    let sfy: Bool
    let qfy: Bool
    let code: Int
    let transUser: User
     */

    struct User: Decodable {
        let nickname: String

        /*
        let id: Int
        let status: Int
        let demand: Int
        let userid: Int
        let uptime: Int
         */
    }

    struct Lyric: Decodable {
        let lyric: String?

        /*
        let version: Int
         */
    }
}
struct QQSearch: Decodable {
    let data: Data
    let code: Int

    struct Data: Decodable {
        let song: Song
        struct Song: Decodable {
            let list: [Item]
            struct Item: Decodable {
                let songmid: String
                let songname: String
                let albumname: String
                let albummid: String
                let albumid: Int?
                let singer: [Singer]
                let interval: Int?
                struct Pay: Decodable {
                    let payalbum: Int
                    let payalbumprice: Int
                    let paydownload: Int
                    let payinfo: Int
                    let payplay: Int
                    let paytrackmouth: Int
                    let paytrackprice: Int
                }
                struct Preview: Decodable {
                    let trybegin: Int
                    let tryend: Int
                    let trysize: Int
                }
                struct Singer: Decodable {
                    let name: String
                }
            }
        }
    }
}

struct QQLyrics: Decodable {
    let retcode: Int
    let code: Int
    let subcode: Int
    let lyric: Data
    let trans: Data?
}
struct QQAlbum: Decodable, Encodable{
    let code: Int
    let data:Album
    struct Album: Decodable, Encodable {
        let album_id:String?
        let album_mid: String
        let album_name: String?
        let headpiclist: [Headpiclist]
        struct Headpiclist: Decodable, Encodable{
            let picurl: String
        }
    }
}
extension QQLyrics {

    var lyricString: String? {
        return String(data: lyric, encoding: .utf8)?.decodingXMLEntities()
    }

    var transString: String? {
        guard let data = trans,
            let string = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return string.decodingXMLEntities()
    }
}

struct OriginalName: Decodable, Encodable {
    let trackName: String
    let artist: String
    let album: String
}

public struct Attachments: Codable, Hashable {
    var content: [Tag: LyricsLineAttachment] = [:]

    subscript(tag: Tag) -> LyricsLineAttachment? {
        get { content[tag] }
        set { content[tag] = newValue }
    }

    enum Tag: String, Codable, Hashable {
        case translation = "tr"

        static func translation() -> Tag { .translation }
    }
}

enum LyricsLineAttachment: Codable, Hashable {
    case plainText(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        self = .plainText(text)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .plainText(let str):
            try container.encode(str)
        }
    }

}
extension LyricsLineAttachment {
    var stringValue: String? {
        if case let .plainText(str) = self {
            return str
        }
        return nil
    }
}

extension String {

    private static let xmlEntities: [Substring: Character] = [
        "&quot;": "\"",
        "&amp;": "&",
        "&apos;": "'",
        "&lt;": "<",
        "&gt;": ">",
    ]

    func decodingXMLEntities() -> String {

        // ===== Utility functions =====

        // Convert the number in the string to the corresponding
        // Unicode character, e.g.
        //    decodeNumeric("64", 10)   --> "@"
        //    decodeNumeric("20ac", 16) --> "€"
        func decodeNumeric(_ string: Substring, base: Int) -> Character? {
            guard let code = UInt32(string, radix: base),
                let uniScalar = UnicodeScalar(code)
            else { return nil }
            return Character(uniScalar)
        }

        // Decode the HTML character entity to the corresponding
        // Unicode character, return `nil` for invalid input.
        //     decode("&#64;")    --> "@"
        //     decode("&#x20ac;") --> "€"
        //     decode("&lt;")     --> "<"
        //     decode("&foo;")    --> nil
        func decode(_ entity: Substring) -> Character? {

            if entity.hasPrefix("&#x") || entity.hasPrefix("&#X") {
                return decodeNumeric(entity.dropFirst(3).dropLast(), base: 16)
            } else if entity.hasPrefix("&#") {
                return decodeNumeric(entity.dropFirst(2).dropLast(), base: 10)
            } else {
                return String.xmlEntities[entity]
            }
        }

        // ===== Method starts here =====

        var result = ""
        var position = startIndex

        // Find the next '&' and copy the characters preceding it to `result`:
        while let ampRange = self[position...].range(of: "&") {
            result.append(contentsOf: self[position..<ampRange.lowerBound])
            position = ampRange.lowerBound

            // Find the next ';' and copy everything from '&' to ';' into `entity`
            guard let semiRange = self[position...].range(of: ";") else {
                // No matching ';'.
                break
            }
            let entity = self[position..<semiRange.upperBound]
            position = semiRange.upperBound

            if let decoded = decode(entity) {
                // Replace by decoded character:
                result.append(decoded)
            } else {
                // Invalid entity, copy verbatim:
                result.append(contentsOf: entity)
            }
        }
        // Copy remaining characters to `result`:
        result.append(contentsOf: self[position...])
        return result
    }
}
