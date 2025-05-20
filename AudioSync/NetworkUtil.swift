import Foundation

public class NetworkUtil {

    var viewModel: ViewModel
    let fakeSpotifyUserAgentconfig = URLSessionConfiguration.default
    let fakeSpotifyUserAgentSession: URLSession
    let decoder = JSONDecoder()
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
        }
        var newName = trackName
        var newArtist = artist
        var newAlbum = album
        if genre == "J-Pop"
            || genre == "Kayokyoku"
        {
            let originalName = try await fetchOriginalName(
                trackName: trackName,
                artist: artist)
            print("日文原始名称: \(originalName)")
            let origTrackName = originalName.trackName
            let origArtist = originalName.artist
            let origAlbum = originalName.album
            if !origTrackName.isEmpty,
                !origArtist.isEmpty,
                !origAlbum.isEmpty
            {
                newName = origTrackName
                newArtist = origArtist
                newAlbum = origAlbum
            }
        }

        let qqLyrics =  await fetchQQLyrics(
            trackName: newName, artist: newArtist, album: newAlbum)
        if !qqLyrics.isEmpty {
            return qqLyrics
        }
        let neteaseLyrics =  await fetchNetEaseLyrics(
            trackName: newName, artist: newArtist, trackID: trackID,
            album: newAlbum)
        if !neteaseLyrics.isEmpty{
            return neteaseLyrics
        }
        await MainActor.run {
            if !viewModel.allCandidates.isEmpty {
                viewModel.needNanualSelection = true
            }
        }
        let selected: CandidateSong =  await withCheckedContinuation { continuation in
            Task { @MainActor in
                viewModel.onCandidateSelected = { song in
                    continuation.resume(returning: song)
                    self.viewModel.onCandidateSelected = nil
                }
            }
        }
        return try await fetchLyricsByID(song: selected)
    }

    func fetchNetEaseLyrics(
        trackName: String, artist: String, trackID: String, album: String
    ) async -> [LyricLine] {
        if let url = URL(
            string:
                "https://neteasecloudmusicapi-ten-wine.vercel.app/search?keywords=\(trackName) \(artist)&limit=5"
        ) {
            do{
                let request = URLRequest(url: url)
                let urlResponseAndData = try await fakeSpotifyUserAgentSession.data(
                    for: request)
                let neteasesearch = try decoder.decode(
                    NetEaseSearch.self, from: urlResponseAndData.0)
                print("netease 搜索歌曲：\(neteasesearch.result.songs)")

                let matchedSong = neteasesearch.result.songs.first {
                    $0.name.normalized == trackName
                        && $0.artists.contains(where: {
                            $0.name.normalized == artist
                        })
                        && ($0.album.name.normalized == album
                            || album.contains($0.album.name.normalized)
                            || $0.album.name.normalized.contains(album))
                }

                guard let song = matchedSong else {
                    print(
                        "❌ 没有匹配到 netease 歌曲：trackName=\(trackName), artist=\(artist), album=\(album)"
                    )
                    // Append all netease songs as candidates
                    for song in neteasesearch.result.songs {
                        let candidate = CandidateSong(
                            id: song.id.codingKey.stringValue,
                            name: song.name,
                            artist: song.artists.map { $0.name }.joined(separator: ", "),
                            album: song.album.name,
                            source: "NetEase"
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
                    try await fakeSpotifyUserAgentSession.data(for: lyricRequest)
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
            }catch{
                print("fetch netease lyrics:\(error)")
            }
        }
        return []
    }

    func fetchQQLyrics(trackName: String, artist: String, album: String)
        async -> [LyricLine]
    {
        if let url = URL(
            string:
                "https://c.y.qq.com/soso/fcgi-bin/client_search_cp?p=1&n=5w=\(trackName) \(artist)"
        ) {
            do{
                let request = URLRequest(url: url)
                let urlResponseAndData = try await fakeSpotifyUserAgentSession.data(
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
                let QQSearchData = try decoder.decode(QQSearch.self, from: jsonData)
                print("qq 搜索歌曲:\(QQSearchData.data.song.list)")
                let QQSong = QQSearchData.data.song.list.first {
                    $0.songname.normalized == trackName
                    && $0.singer.contains(where: {
                        $0.name.normalized == artist
                    })
                    && ($0.albumname.normalized == album
                        || album.contains($0.albumname.normalized)
                        || $0.albumname.normalized.contains(album))
                }
                if QQSong == nil {
                    print(
                        "❌ 没有匹配到 QQ 歌曲：trackName=\(trackName), artist=\(artist), album=\(album)"
                    )
                    // Append all QQ songs as candidates
                    for song in QQSearchData.data.song.list {
                        let candidate = CandidateSong(
                            id: song.songmid,
                            name: song.songname,
                            artist: song.singer.map { $0.name }.joined(separator: ", "),
                            album: song.albumname,
                            source: "QQ"
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
                print("qq lyricParse \(lyricsParser.lyrics)")
                return lyricsParser.lyrics
            }catch{
                print("fetch qq lyrics : \(error)")
            }
        }
        return []
    }
    func fetchOriginalName(trackName: String, artist: String) async throws
        -> OriginalName
    {
        let url = URL(string: "https://api.siliconflow.cn/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Bearer sk-gliblrzjfhukxueioulgpcnnhnbleypfichdulyfzjquidwg",
            forHTTPHeaderField: "Authorization")
        let payload: [String: Any] = [
            "model": "deepseek-ai/DeepSeek-R1",
            "messages": [
                [
                    "role": "system",
                    "content":
                        "You are very familiar with Japanese music and proficient in Japanese (including Japanese-style Romanization). Help me find the original Japanese song title and artist name. Wrap the song title in <>, Wrap the album title in [] and the artist name in {},and if there is a year and the word 'live' they should be retained. Your answer should omit the thinking process and analysis. Response format example: <涙そうそう 1997 live> [南風] {夏川 りみ} ",
                ],
                ["role": "user", "content": "歌名: \(trackName), 歌手: \(artist)"],
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
        case "NetEase":
            let lyricRequest = URLRequest(
                url: URL(
                    string:
                        "https://neteasecloudmusicapi-ten-wine.vercel.app/lyric?id=\(song.id)"
                )!)
            let urlResponseAndDataLyrics =
                try await fakeSpotifyUserAgentSession.data(for: lyricRequest)
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
        case "QQ":
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
            let qqLyricsData = try decoder.decode(
                QQLyrics.self, from: lyrJsonData)
            guard let lyricString = qqLyricsData.lyricString else {
                return []
            }
            let lyricsParser = LyricsParser(lyrics: lyricString, format: .qq)
            if let tlyricString = qqLyricsData.transString {
                print("qq lyricString:\(tlyricString)")
                let tlyricsParser = LyricsParser(
                    lyrics: tlyricString, format: .qq)
                return lyricsParser.mergeLyrics(translation: tlyricsParser)
            }
            print("qq lyricParse \(lyricsParser.lyrics)")
            return lyricsParser.lyrics
        default:
            return []
        }
    }
}

extension String {
    var normalized: String {
        self
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .lowercased()
    }
}
