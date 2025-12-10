import Foundation

actor CoverCache {
    private var cache: [String: CacheEntry] = [:]
    private var accessOrder: [String] = []  // LRU 队列
    private let maxMemorySize: Int = 100 * 1024 * 1024  // 100MB
    private var currentSize: Int = 0

    struct CacheEntry {
        let data: Data
        let size: Int
    }

    func get(for key: String) -> Data? {
        guard let entry = cache[key] else { return nil }

        // 更新 LRU（将 key 移到队尾）
        if let idx = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: idx)
        }
        accessOrder.append(key)

        return entry.data
    }

    func set(_ data: Data, for key: String) {
        let size = data.count

        // 如果已存在则先移除
        if let old = cache[key] {
            currentSize -= old.size
            cache.removeValue(forKey: key)
            accessOrder.removeAll(where: { $0 == key })
        }

        // 插入新值
        cache[key] = CacheEntry(data: data, size: size)
        accessOrder.append(key)
        currentSize += size

        // 内存超出限制 -> 逐个淘汰 LRU
        trimIfNeeded()
    }

    private func trimIfNeeded() {
        while currentSize > maxMemorySize, let oldestKey = accessOrder.first {
            if let entry = cache[oldestKey] {
                currentSize -= entry.size
            }
            cache.removeValue(forKey: oldestKey)
            accessOrder.removeFirst()
        }
    }
}
actor NetWorkQueue {
    private var queue: [String] = []

    func contains(_ key: String) -> Bool {
        return queue.contains(key)
    }

    func append(_ key: String) {
        queue.append(key)
    }
    func remove(_ key: String) {
        if let index = queue.firstIndex(of: key) {
            queue.remove(at: index)
        }
    }
}

actor ItunesSongCache {
    private var cache: [String: SongSearchResult.Song] = [:]
    private var ongoingTasks: [String: Task<SongSearchResult.Song, Error>] = [:]
    private var keysOrder: [String] = []
    private let maxSize: Int
    init(maxSize: Int = 30) {
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
}
