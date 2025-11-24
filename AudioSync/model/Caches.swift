actor CoverCache {
    private var cache: [String: String] = [:]
    private var keysOrder: [String] = []
    private let maxSize: Int
    init(maxSize: Int = 30) {
        self.maxSize = maxSize
    }
    func get(for key: String) -> String? {
        return cache[key]
    }

    func set(_ url: String, for key: String) {
        if cache[key] == nil {
            keysOrder.append(key)
        }
        cache[key] = url
        enforceLimit()
    }
    private func enforceLimit() {
        while keysOrder.count > maxSize {
            let oldestKey = keysOrder.removeFirst()
            cache[oldestKey] = nil
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
