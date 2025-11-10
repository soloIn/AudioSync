import AppKit
import Foundation

// MARK: - 1. JSON 解析模型
/// 用于解析 iTunes Search API 响应的结构体。我们只需要 Artist ID。
struct ArtistSearchResult: Decodable {
    let results: [Artist]

    struct Artist: Decodable {
        let artistId: Int
        let artistName: String
        // 允许获取其他信息，如商店代码，但我们只聚焦于 ID
    }
}
struct SongSearchResult: Decodable {
    let results: [SongSearchResult.Song]

    struct Song: Decodable {
        let artistId: Int
        let trackId: Int
        let artistName: String
        let trackName: String
        let collectionName: String
        let artworkUrl: String

        enum CodingKeys: String, CodingKey {
            case artistId, trackId, artistName, trackName, collectionName
            case artworkUrl = "artworkUrl100"
        }
    }
}
// MARK: - 2. 导航辅助枚举
public enum IDFetchError: Error, LocalizedError {
    case networkError(Error)
    case dataParsingError
    case NotFound
    case invalidURL

    public var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "网络请求失败: \(error.localizedDescription)"
        case .dataParsingError:
            return "数据解析失败，JSON结构可能已更改。"
        case .NotFound:
            return "未找到匹配的艺术家或歌曲。"
        case .invalidURL:
            return "URL 构造失败。"
        }
    }
}
actor SongCache {
    private var cache: [String: SongSearchResult.Song] = [:]
    private var ongoingTasks: [String: Task<SongSearchResult.Song, Error>] = [:]
    private var keysOrder: [String] = []
    private let maxSize: Int
    init(maxSize: Int = 100) {
        self.maxSize = maxSize
    }
    func get(for key: String) -> SongSearchResult.Song? {
        return cache[key]
    }

    func set(_ song: SongSearchResult.Song, for key: String) {
        if cache[key] == nil {
            keysOrder.append(key)
        }
        cache[key] = song
        ongoingTasks[key] = nil
        enforceLimit()
    }
    private func enforceLimit() {
        while keysOrder.count > maxSize {
            let oldestKey = keysOrder.removeFirst()
            cache[oldestKey] = nil
        }
    }
    func task(for key: String) -> Task<SongSearchResult.Song, Error>? {
        return ongoingTasks[key]
    }

    func setTask(_ task: Task<SongSearchResult.Song, Error>, for key: String) {
        ongoingTasks[key] = task
    }
    func removeTask(for key: String) {
        ongoingTasks[key] = nil
    }
}  // MARK: - 3. ID 获取器
public enum IDFetcher {
    private static let songCacheActor = SongCache()
    private static func safeCacheKey(
        for name: String,
        artist: String,
        countryCode: String
    ) -> String {
        let rawKey =
            "\(name.lowercased())_\(artist.lowercased())_\(countryCode.lowercased())"
        if let data = rawKey.data(using: .utf8) {
            return data.base64EncodedString()
        }
        return rawKey
    }
    public static func fetchArtistID(
        name: String,
        artist: String,
        countryCode: String = "cn"
    ) async throws -> Int {
        let song = try await fetchSong(by: name, by: artist)
        return song.artistId
    }

    public static func fetchTrackID(
        name: String,
        artist: String,
        countryCode: String = "cn"
    ) async throws -> Int {
        let song = try await fetchSong(by: name, by: artist)
        return song.trackId
    }

    public static func fetchArtworkData(
        name: String,
        artist: String,
        countryCode: String = "cn"
    ) async throws -> NSImage {
        let song = try await fetchSong(by: name, by: artist)
        // 1. 构造 URL
        guard let url = URL(string: song.artworkUrl) else {
            throw IDFetchError.invalidURL
        }

        // 2. 下载图片数据
        let (data, _) = try await URLSession.shared.data(from: url)

        // 3. 创建 NSImage
        guard let image = NSImage(data: data) else {
            throw IDFetchError.dataParsingError
        }

        return image
    }
    private static func fetchSong(
        by name: String,
        by artist: String,
        countryCode: String = "cn"
    ) async throws -> SongSearchResult.Song {

        let cacheKey = safeCacheKey(
            for: name,
            artist: artist,
            countryCode: countryCode
        )
        // 1. 先检查缓存
        if let cachedSong = await songCacheActor.get(for: cacheKey) {
            Log.backend.debug("命中缓存:\(name) - \(artist)")
            return cachedSong
        }

        // 2. 再检查是否有正在进行的任务
        if let ongoingTask = await songCacheActor.task(for: cacheKey) {
            return try await ongoingTask.value
        }
        // 3. 如果没有，就创建一个新任务
        let task = Task<SongSearchResult.Song, Error> {
            defer { Task { await songCacheActor.removeTask(for: cacheKey) } }

            let song = try await fetchSongFromNetwork(
                name: name,
                artist: artist,
                countryCode: countryCode
            )

            await songCacheActor.set(song, for: cacheKey)
            return song
        }

        // 4. 保存任务到 actor
        await songCacheActor.setTask(task, for: cacheKey)

        // 5. 等待任务完成
        return try await task.value
    }
    private static func fetchSongFromNetwork(
        name: String,
        artist: String,
        countryCode: String = "cn"
    ) async throws -> SongSearchResult.Song {
        // 1. URL 构造
        let baseURL = "https://itunes.apple.com/search"

        // 对名字进行 URL 编码，以处理空格和特殊字符
        let term = "\(name) \(artist)"
        guard
            let encodedTerm = term.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
            )
        else {
            throw IDFetchError.invalidURL
        }

        // 设置搜索参数: term=艺术家名字, entity=allArtist, media=music, limit=1
        let urlString =
            "\(baseURL)?term=\(encodedTerm)&entity=musicTrack&media=music&limit=1&country=\(countryCode)"

        guard let url = URL(string: urlString) else {
            throw IDFetchError.invalidURL
        }

        Log.backend.debug("正在查询 iTunes Search API: \(url.absoluteString)")

        // 2. 网络请求
        let (data, _) = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            // 使用 URLSession 发起请求
            let task = URLSession.shared.dataTask(with: url) {
                data,
                response,
                error in
                if let error = error {
                    continuation.resume(
                        throwing: IDFetchError.networkError(error)
                    )
                    return
                }
                guard let data = data else {
                    continuation.resume(throwing: IDFetchError.dataParsingError)
                    return
                }
                continuation.resume(returning: (data, response!))
            }
            task.resume()
        }

        // 3. JSON 解析
        do {
            let decoder = JSONDecoder()
            let songResult = try decoder.decode(
                SongSearchResult.self,
                from: data
            )

            guard let firstSong = songResult.results.first else {
                throw IDFetchError.NotFound
            }
            return firstSong

        } catch {
            // 可能是 JSON 解码错误或艺术家未找到
            if error is IDFetchError {
                throw error
            }
            throw IDFetchError.dataParsingError
        }
    }
}
