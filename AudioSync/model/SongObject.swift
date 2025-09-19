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
            Log.general.error("保存 coreData 失败：\(error)")
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
            Log.general.error("根据 id = \(id) 获取 coreData 失败：\(error)")
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
                Log.general.info("删除缓存: \(song.trackName) - \(song.id)")
                try context.save()
            }
        } catch {
            Log.general.error("删除 id = \(id) 的 coreData 失败：\(error)")
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
            Log.general.error("删除所有 coreData 失败：\(error)")
        }
    }
    @nonobjc public class func typedFetchRequest() -> NSFetchRequest<SongObject>
    {
        return NSFetchRequest<SongObject>(entityName: "SongObject")
    }

}
