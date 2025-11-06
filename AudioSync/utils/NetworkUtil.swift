import Foundation
public class NetworkUtil {
    
    var viewModel: ViewModel
    let fakeSpotifyUserAgentconfig = URLSessionConfiguration.default
    let fakeSpotifyUserAgentSession: URLSession
    
    init(viewModel: ViewModel) {
        fakeSpotifyUserAgentSession = URLSession(
            configuration: fakeSpotifyUserAgentconfig)
        self.viewModel = viewModel
    }
    func fetchLyrics(
        trackName: String, artist: String, trackID: String, album: String,
        genre: String
    ) async throws -> [LyricLine] {
        await MainActor.run {
            viewModel.allCandidates.removeAll()
            viewModel.needNanualSelection = false
        }
        var effectiveTrackName = trackName
        var effectiveArtist = artist
        var effectiveAlbum = album
        if ["J-Pop", "Kayokyoku", "J-Rock"].contains(genre) {
            Log.general.info("获取日文原名...")
            let originalNameResult = try await fetchOriginalName(
                trackName: trackName,
                artist: artist,
                album: album)
            Log.general.info("日文原名: \(JSON.stringify(originalNameResult))")
            if !originalNameResult.trackName.isEmpty {
                effectiveTrackName = originalNameResult.trackName
            }
            if !originalNameResult.artist.isEmpty {
                effectiveArtist = originalNameResult.artist
            }
            if !originalNameResult.album.isEmpty {
                effectiveAlbum = originalNameResult.album
            }
        }
        // 尝试网易云音乐
        var lyrics = await fetchNetEaseLyrics(
            trackName: effectiveTrackName, artist: effectiveArtist,
            trackID: trackID,  // trackID 似乎未使用，但保持签名一致
            album: effectiveAlbum)
        if !lyrics.isEmpty {
            return lyrics
        }
        
        // 尝试 QQ 音乐
        lyrics = await fetchQQLyrics(
            trackName: effectiveTrackName, artist: effectiveArtist,
            album: effectiveAlbum)
        if !lyrics.isEmpty {
            return lyrics
        }
        
        // 如果上述都失败，并且收集到了候选歌曲，则触发手动选择
        // 先获取QQ音乐的封面
        await fetchAlbumCover()
        
        // 检查是否有候选歌曲，并触发手动选择流程
        // 在 MainActor 上更新 UI 相关状态
        let shouldAskForManualSelection = await MainActor.run { () -> Bool in
            if !self.viewModel.allCandidates.isEmpty {
                self.viewModel.needNanualSelection = true
                Log.general.info("需要手动选择 -> true")
                return true
            }
            return false
        }
        if shouldAskForManualSelection {
            Log.general.info("等待用户手动选择...")
            // 为 continuation 添加超时机制
            let continuationTimeout: TimeInterval = 10.0  // 例如 10 秒超时
            
            do {
                let selectedSong: CandidateSong =
                try await withCheckedThrowingContinuation { continuation in
                    Task {
                        try? await Task.sleep(
                            nanoseconds: UInt64(
                                continuationTimeout * 1_000_000_000))
                        await MainActor.run {
                            if self.viewModel.onCandidateSelected != nil {
                                Log.general.warning("⚠️ 选择超时")
                                self.viewModel.onCandidateSelected = nil
                                self.viewModel.needNanualSelection = false
                                continuation.resume(
                                    throwing: FetchError
                                        .manualSelectionTimeout)
                            }
                        }
                    }
                    
                    Task { @MainActor in
                        self.viewModel.onCandidateSelected = { song in
                            self.viewModel.onCandidateSelected = nil  // 清理回调
                            continuation.resume(returning: song)
                        }
                    }
                }
                // 用户选择后，根据 ID 获取歌词
                return try await fetchLyricsByID(song: selectedSong)
            } catch FetchError.manualSelectionTimeout {
                await MainActor.run {
                    self.viewModel.needNanualSelection = false  // 确保UI状态被重置
                }
                return []  // 或抛出错误
            } catch {
                Log.general.error("手动选择发生错误: \(error)")
                await MainActor.run {
                    self.viewModel.needNanualSelection = false  // 确保UI状态被重置
                }
                throw error  // 重新抛出其他错误
            }
        }
        return []
    }
    
    // 定义一个错误类型用于超时
    enum FetchError: Error {
        case manualSelectionTimeout
        case apiError(String)
        case parsingError(String)
    }
    
    func fetchNetEaseLyrics(
        trackName: String, artist: String, trackID: String, album: String
    ) async -> [LyricLine] {
        if let url = URL(
            string:
                "https://neteasecloudmusicapi-ten-wine.vercel.app/cloudsearch?keywords=\(trackName) \(artist)&limit=5"
        ) {
            do {
                let request = URLRequest(url: url)
                let urlResponseAndData =
                try await fakeSpotifyUserAgentSession.data(
                    for: request)
                let decoder = JSONDecoder()
                let neteasesearch = try decoder.decode(
                    NetEaseSearch.self, from: urlResponseAndData.0)
                Log.general.info("netease 找到歌曲：\(neteasesearch.result.songs)")
                
                let matchedSong = neteasesearch.result.songs.first {
                    $0.name.normalized == trackName.normalized
                    && $0.ar.contains(where: {
                        $0.name.normalized == artist.normalized
                    })
                    && ($0.al.name.normalized == album.normalized
                        || album.normalized.contains(
                            $0.al.name.normalized)
                        || $0.al.name.normalized.contains(
                            album.normalized))
                }
                
                guard let song = matchedSong else {
                    Log.general.info("❌ 没有匹配到 netease 歌曲：trackName=\(trackName), artist=\(artist), album=\(album)")
                    // Append all netease songs as candidates
                    for song in neteasesearch.result.songs {
                        let candidate = CandidateSong(
                            id: song.id.codingKey.stringValue,
                            name: song.name,
                            artist: song.ar.map { $0.name }.joined(
                                separator: ", "),
                            album: song.al.name,
                            albumId: song.al.id.codingKey.stringValue,
                            albumCover: song.al.picUrl,
                            source: .netEase
                        )
                        await MainActor.run {
                            viewModel.allCandidates.append(candidate)
                        }
                    }
                    return []
                }
                
                let lyricRequest = URLRequest(
                    url: URL(
                        string:
                            "https://neteasecloudmusicapi-ten-wine.vercel.app/lyric?id=\(song.id)"
                    )!)
                let urlResponseAndDataLyrics =
                try await fakeSpotifyUserAgentSession.data(
                    for: lyricRequest)
                
                let neteaseLyrics = try decoder.decode(
                    NetEaseLyrics.self, from: urlResponseAndDataLyrics.0)
                
                guard let neteaselrc = neteaseLyrics.lrc,
                      let neteaseLrcString = neteaselrc.lyric
                else {
                    return []
                }
                
                let originalParser = LyricsParser(
                    lyrics: neteaseLrcString, format: .netEase)
                var finalLyrics = originalParser.lyrics
                
                // 合并歌词翻译
                if let tlyric = neteaseLyrics.tlyric,
                   let tlyricString = tlyric.lyric, !tlyricString.isEmpty
                {
                    let translationParser = LyricsParser(
                        lyrics: tlyricString, format: .netEase)
                    if !translationParser.lyrics.isEmpty {
                        finalLyrics = originalParser.mergeLyrics(
                            translation: translationParser)
                    }
                }
                return finalLyrics
            } catch {
                Log.general.error("fetch netease lyrics:\(error)")
            }
        }
        return []
    }
    
    func fetchQQLyrics(trackName: String, artist: String, album: String)
    async -> [LyricLine]
    {
        if let url = URL(
            string:
                "https://c.y.qq.com/soso/fcgi-bin/client_search_cp?p=1&n=5&w=\(trackName) \(artist)"
        ) {
            do {
                let request = URLRequest(url: url)
                let urlResponseAndData =
                try await fakeSpotifyUserAgentSession.data(
                    for: request)
                guard
                    let rawText = String(
                        data: urlResponseAndData.0, encoding: .utf8),
                    let rangeStart = rawText.range(of: "("),
                    let rangeEnd = rawText.range(of: ")", options: .backwards)
                else {
                    return []
                }
                let jsonString = String(
                    rawText[rangeStart.upperBound..<rangeEnd.lowerBound])
                guard let jsonData = jsonString.data(using: .utf8) else {
                    return []
                }
                let decoder = JSONDecoder()
                let QQSearchData = try decoder.decode(
                    QQSearch.self, from: jsonData)
                Log.general.info("qq 找到歌曲:\(QQSearchData.data.song.list)")
                let QQSong = QQSearchData.data.song.list.first {
                    $0.songname.normalized == trackName.normalized
                    && $0.singer.contains(where: {
                        $0.name.normalized == artist.normalized
                    })
                    && ($0.albumname.normalized == album.normalized
                        || album.normalized.contains(
                            $0.albumname.normalized)
                        || $0.albumname.normalized.contains(
                            album.normalized))
                }
                if QQSong == nil {
                    Log.general.info("❌ 没有匹配到 QQ 歌曲：trackName=\(trackName), artist=\(artist), album=\(album)")
                    // Append all QQ songs as candidates
                    for song in QQSearchData.data.song.list {
                        let candidate = CandidateSong(
                            id: song.songmid,
                            name: song.songname,
                            artist: song.singer.map { $0.name }.joined(
                                separator: ", "),
                            album: song.albumname,
                            albumId: song.albummid,
                            albumCover: "",
                            source: .qq
                        )
                        await MainActor.run {
                            viewModel.allCandidates.append(candidate)
                        }
                    }
                    return []
                }
                let url = URL(
                    string:
                        "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=\(QQSong!.songmid)&g_tk=5381"
                )!
                var lyricRequest = URLRequest(url: url)
                lyricRequest.setValue(
                    "y.qq.com/portal/player.html", forHTTPHeaderField: "Referer"
                )
                
                let lyricResponseAndData =
                try await fakeSpotifyUserAgentSession.data(
                    for: lyricRequest)
                
                guard
                    let lyrRawText = String(
                        data: lyricResponseAndData.0, encoding: .utf8),
                    let lyrRangeStart = lyrRawText.range(of: "("),
                    let lyrRangeEnd = lyrRawText.range(
                        of: ")", options: .backwards)
                else {
                    return []
                }
                let lyrJsonString = String(
                    lyrRawText[
                        lyrRangeStart.upperBound..<lyrRangeEnd.lowerBound])
                guard let lyrJsonData = lyrJsonString.data(using: .utf8) else {
                    return []
                }
                
                let qqLyricsData = try decoder.decode(
                    QQLyrics.self, from: lyrJsonData)
                guard let lyricString = qqLyricsData.lyricString else {
                    return []
                }
                let lyricsParser = LyricsParser(
                    lyrics: lyricString, format: .qq)
                if let tlyricString = qqLyricsData.transString {
                    let tlyricsParser = LyricsParser(
                        lyrics: tlyricString, format: .qq)
                    return lyricsParser.mergeLyrics(translation: tlyricsParser)
                }
                return lyricsParser.lyrics
            } catch {
                Log.general.error("fetch qq lyrics : \(error)")
            }
        }
        return []
    }
    func fetchOriginalName(trackName: String, artist: String, album: String)
    async throws
    -> OriginalName
    {
        let url = URL(string: "https://api.siliconflow.cn/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Bearer your-key",
            forHTTPHeaderField: "Authorization")
        let payload: [String: Any] = [
            "model": "deepseek-ai/DeepSeek-R1",
            "messages": [
                [
                    "role": "system",
                    "content":
                        "You are very familiar with Japanese music and proficient in Japanese (including Japanese-style Romanization). Help me find the original Japanese song title and artist name. Wrap the song title in <>, Wrap the album title in [] and the artist name in {},and if there is a year and the word 'live' they should be retained. Your answer should omit the thinking process and analysis. Response format example: <涙そうそう 1997 live> [南風] {夏川 りみ} ",
                ],
                [
                    "role": "user",
                    "content": "歌名: \(trackName), 歌手: \(artist), 专辑: \(album)",
                ],
            ],
            "stream": false,
        ]
        
        request.httpBody = try JSONSerialization.data(
            withJSONObject: payload, options: [])
        
        let (data, _) = try await fakeSpotifyUserAgentSession.data(for: request)
        struct CompletionResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }
        let decoder = JSONDecoder()
        let response = try decoder.decode(CompletionResponse.self, from: data)
        let rawContent = response.choices.first?.message.content ?? ""
        let originalName = rawContent.trimmingCharacters(
            in: CharacterSet(charactersIn: "<>"))
        let artist = rawContent.trimmingCharacters(
            in: CharacterSet(charactersIn: "{}"))
        let album = rawContent.trimmingCharacters(
            in: CharacterSet(charactersIn: "[]"))
        return OriginalName(
            trackName: originalName, artist: artist, album: album)
    }
    
    func fetchLyricsByID(song: CandidateSong) async throws -> [LyricLine] {
        switch song.source {
        case .netEase:
            let lyricRequest = URLRequest(
                url: URL(
                    string:
                        "https://neteasecloudmusicapi-ten-wine.vercel.app/lyric?id=\(song.id)"
                )!)
            let urlResponseAndDataLyrics =
            try await fakeSpotifyUserAgentSession.data(for: lyricRequest)
            let decoder = JSONDecoder()
            let neteaseLyrics = try decoder.decode(
                NetEaseLyrics.self, from: urlResponseAndDataLyrics.0)
            
            guard let neteaselrc = neteaseLyrics.lrc,
                  let neteaseLrcString = neteaselrc.lyric
            else {
                return []
            }
            
            let originalParser = LyricsParser(
                lyrics: neteaseLrcString, format: .netEase)
            
            guard let tlrc = neteaseLyrics.tlyric, let tlrcString = tlrc.lyric
            else {
                return originalParser.lyrics
            }
            let translationParser = LyricsParser(
                lyrics: tlrcString, format: .netEase)
            return originalParser.mergeLyrics(translation: translationParser)
        case .qq:
            let url = URL(
                string:
                    "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=\(song.id)&g_tk=5381"
            )!
            var lyricRequest = URLRequest(url: url)
            lyricRequest.setValue(
                "y.qq.com/portal/player.html", forHTTPHeaderField: "Referer")
            
            let lyricResponseAndData =
            try await fakeSpotifyUserAgentSession.data(for: lyricRequest)
            
            guard
                let lyrRawText = String(
                    data: lyricResponseAndData.0, encoding: .utf8),
                let lyrRangeStart = lyrRawText.range(of: "("),
                let lyrRangeEnd = lyrRawText.range(of: ")", options: .backwards)
            else {
                return []
            }
            let lyrJsonString = String(
                lyrRawText[lyrRangeStart.upperBound..<lyrRangeEnd.lowerBound])
            guard let lyrJsonData = lyrJsonString.data(using: .utf8) else {
                return []
            }
            let decoder = JSONDecoder()
            let qqLyricsData = try decoder.decode(
                QQLyrics.self, from: lyrJsonData)
            guard let lyricString = qqLyricsData.lyricString else {
                return []
            }
            let lyricsParser = LyricsParser(lyrics: lyricString, format: .qq)
            if let tlyricString = qqLyricsData.transString {
                let tlyricsParser = LyricsParser(
                    lyrics: tlyricString, format: .qq)
                return lyricsParser.mergeLyrics(translation: tlyricsParser)
            }
            return lyricsParser.lyrics
        }
    }
    func fetchAlbumCover() async {
        let qq = await MainActor.run { () -> ([String]) in
            var qqCandidates: [String] = []
            for candidate in viewModel.allCandidates {
                switch candidate.source {
                case .qq:
                    if !candidate.albumId.isEmpty {
                        qqCandidates.append(candidate.albumId)
                    }
                case .netEase:
                    break
                }
            }
            return qqCandidates
        }
        
        await withTaskGroup(of: (String, String).self) { group in
            for id in qq {
                group.addTask {
                    let cover =
                    (try? await self.fetchQQAlbumCoverByID(id: id)) ?? ""
                    return (id, cover)
                }
            }
            
            let coverMap = await group.reduce(into: [String: String]()) {
                $0[$1.0] = $1.1
            }
            
            await MainActor.run {
                for i in 0..<viewModel.allCandidates.count {
                    let candidate = viewModel.allCandidates[i]
                    if candidate.source == .qq,
                       let cover = coverMap[candidate.albumId]
                    {
                        viewModel.allCandidates[i].albumCover = cover
                    }
                }
            }
        }
    }
    func fetchQQAlbumCoverByID(id: String) async throws -> String {
        do {
            let albumRequest = URLRequest(
                url: URL(
                    string:
                        "https://c.y.qq.com/v8/fcg-bin/musicmall.fcg?albummid=\(id)&format=json&inCharset=utf-8&outCharset=utf-8&cmd=get_album_buy_page"
                )!)
            let albumData = try await fakeSpotifyUserAgentSession.data(
                for: albumRequest)
            let decoder = JSONDecoder()
            let album = try decoder.decode(QQAlbum.self, from: albumData.0)
            guard let pic = album.data.headpiclist.first?.picurl else {
                Log.general.error("辑封面获取失败: \(JSON.stringify(album))")
                return ""
            }
            Log.general.info("专辑 url: \(pic) ")
            return pic
            
        } catch {
            Log.general.error("获取专辑 \(error)")
        }
        return ""
    }
    func fetchSimilarArtists(name: String) async throws -> [Artist] {
        let request = URLRequest(url: URL(string: "http://ws.audioscrobbler.com/2.0/?method=artist.getsimilar&artist=\(name)&api_key=7c53dde26c531f5d311fd23734b54150&limit=10&format=json")!)
        let response = try await fakeSpotifyUserAgentSession.data(for: request)
        let decoder = JSONDecoder()
        if let str = String(data: response.0, encoding: .utf8) {
            Log.general.info("原始响应：\(str)")
        }
        let artistResponse = try decoder.decode(ArtistResponse.self, from: response.0)
        Log.general.info("response: \(JSON.stringify(artistResponse))")
        guard let similars = artistResponse.similarartists?.artist else {return []}
        var similarArtists: [Artist] = []
        similars.forEach{
            let similarArtist = Artist(name: $0.name, url: $0.url ?? "", mbid: $0.mbid ?? "")
            similarArtists.append(similarArtist)
        }
        return similarArtists
    }
}

extension String {
    var normalized: String {
        self
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "(", with: "-")
            .replacingOccurrences(of: ")", with: "-")
            .replacingOccurrences(of: "：", with: "-")
            .replacingOccurrences(of: "（", with: "-")
            .replacingOccurrences(of: "）", with: "-")
            .lowercased()
    }
}
