import CoreData
import Foundation

@objc(SongObject)
public class SongObject: NSManagedObject, Encodable {
    @NSManaged public var id: String
    @NSManaged public var trackName: String
    @NSManaged public var lyricsData: Data?

    var lyrics: [LyricLine] {
        get {
            guard let data = lyricsData else { return [] }
            return (try? JSONDecoder().decode([LyricLine].self, from: data))
                ?? []
        }
        set {
            lyricsData = try? JSONEncoder().encode(newValue)
        }
    }

    public func setLyrics(_ lines: [LyricLine]) {
        lyrics = lines
    }

    public func getLyrics() -> [LyricLine] {
        return lyrics
    }
}

extension SongObject {

    public static func saveSong(
        id: String, trackName: String, lyrics: [LyricLine],
        in context: NSManagedObjectContext
    ) {
        let song = SongObject(context: context)
        song.id = String(id)
        song.trackName = trackName
        song.setLyrics(lyrics)
        do {
            try context.save()
        } catch {
            #if DEBUG
            print("保存 SongObject 失败：\(error)")
            #endif
        }
    }

    public static func fetchSong(
        byID id: String, context: NSManagedObjectContext
    ) -> SongObject? {
        let request = SongObject.typedFetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        do {
            return try context.fetch(request).first
        } catch {
            #if DEBUG
            print("根据 ID 获取 SongObject 失败：\(error)")
            #endif
            return nil
        }
    }

    public static func deleteSong(byID id: String, context: NSManagedObjectContext) {
        let request = SongObject.typedFetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        do {
            if let song = try context.fetch(request).first {
                context.delete(song)
                #if DEBUG
                print("删除缓存: \(song.trackName) - \(song.id)")
                #endif
                try context.save()
            }
        } catch {
            #if DEBUG
            print("删除指定 ID 的 SongObject 失败：\(error)")
            #endif
        }
    }

    public static func deleteAllSongs(in context: NSManagedObjectContext) {
        let request = SongObject.typedFetchRequest()
        do {
            let songs = try context.fetch(request)
            for song in songs {
                context.delete(song)
            }
            try context.save()
        } catch {
            #if DEBUG
            print("删除所有 SongObject 失败：\(error)")
            #endif
        }
    }
    @nonobjc public class func typedFetchRequest() -> NSFetchRequest<SongObject>
    {
        return NSFetchRequest<SongObject>(entityName: "SongObject")
    }

}
