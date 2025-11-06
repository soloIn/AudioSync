//
//  LyricsParser.swift
//  SpotlightLyrics
//
//  Created by Scott Rong on 2017/4/2.
//  Copyright © 2017 Scott Rong. All rights reserved.
//

import Foundation
import Regex

public enum LyricsFormat: Sendable {
    case netEase  // 原始 LRC 格式
    case qq  // QQ 歌词格式
}

public class LyricsParser {

    let lyricsLineRegex = Regex(
        #"^(\[[+-]?\d+:\d+(?:\.\d+)?\])+(?!\[)([^【\n\r]*)(?:【(.*)】)?"#,
        options: .anchorsMatchLines)

    public var header: LyricsHeader
    public private(set) var lyrics: [LyricLine] = []

    // MARK: Initializers

    public init(lyrics: String, format: LyricsFormat) {
        header = LyricsHeader()
        switch format {
        case .netEase:
            commonInit(lyrics: lyrics)
        case .qq:
            QQLyricInit(lyrics)
        }
    }

    private func commonInit(lyrics: String) {
        header = LyricsHeader()
        parse(lyrics: lyrics)
    }

    // MARK: Privates

    private func parse(lyrics: String) {
        let lines =
            lyrics
            .replacingOccurrences(of: "\\n", with: "\n")
            .trimmingCharacters(in: .quotes)
            .trimmingCharacters(in: .newlines)
            .components(separatedBy: .newlines)

        for line in lines {
            parseLine(line: line)
        }

        // sort by time
        self.lyrics.sort { $0.startTimeMS < $1.startTimeMS }
    }

    private func parseLine(line: String) {
        guard let line = line.blankToNil() else {
            return
        }

        //        if let title = parseHeader(prefix: "ti", line: line) {
        //            header.title = title
        //            return
        //        }
        //        if let author = parseHeader(prefix: "ar", line: line) {
        //            header.author = author
        //            return
        //        }
        //        if let album = parseHeader(prefix: "al", line: line) {
        //            header.album = album
        //            return
        //        }
        //        if let by = parseHeader(prefix: "by", line: line) {
        //            header.by = by
        //            return
        //        }
        if let offset = parseHeader(prefix: "offset", line: line) {
            header.offset = TimeInterval(offset) ?? 0
            return
        }
        if !line.hasSuffix("]") {
            lyrics += parseLyric(line: line)
        }
        //        if let editor = parseHeader(prefix: "re", line: line) {
        //            header.editor = editor
        //            return
        //        }
        //        if let version = parseHeader(prefix: "ve", line: line) {
        //            header.version = version
        //            return
        //        }

    }

    private func parseHeader(prefix: String, line: String) -> String? {
        if line.hasPrefix("[" + prefix + ":") && line.hasSuffix("]") {
            let startIndex = line.index(
                line.startIndex, offsetBy: prefix.count + 2)
            let endIndex = line.index(line.endIndex, offsetBy: -1)
            return String(line[startIndex..<endIndex])
        } else {
            return nil
        }
    }

    private func parseLyric(line: String) -> [LyricLine] {
        var cLine = line
        var items: [LyricLine] = []
        while cLine.hasPrefix("[") {
            guard let closureIndex = cLine.range(of: "]")?.lowerBound else {
                break
            }

            let startIndex = cLine.index(cLine.startIndex, offsetBy: 1)
            let endIndex = cLine.index(closureIndex, offsetBy: -1)
            let amidString = String(cLine[startIndex..<endIndex])

            let amidStrings = amidString.components(separatedBy: ":")
            var hour: TimeInterval = 0
            var minute: TimeInterval = 0
            var second: TimeInterval = 0
            if amidStrings.count >= 1 {
                second = TimeInterval(amidStrings[amidStrings.count - 1]) ?? 0
            }
            if amidStrings.count >= 2 {
                minute = TimeInterval(amidStrings[amidStrings.count - 2]) ?? 0
            }
            if amidStrings.count >= 3 {
                hour = TimeInterval(amidStrings[amidStrings.count - 3]) ?? 0
            }
            cLine.removeSubrange(
                cLine.startIndex..<cLine.index(closureIndex, offsetBy: 1))
            cLine = cLine.trimmingCharacters(in: .whitespaces)
            // Create a LyricLine with the calculated start time and the remaining line as the words
            let lyricLine = LyricLine(
                startTime: 1000
                    * (hour * 3600 + minute * 60 + second + header.offset),
                words: cLine)
            items.append(lyricLine)
        }

        return items
    }

    func mergeLyrics(translation: LyricsParser, threshold: TimeInterval = 0.02)
        -> [LyricLine]
    {
        var merged: [LyricLine] = []
        var i = 0
        var j = 0

        let originalLines = self.lyrics
        let translationLines = translation.lyrics

        while i < originalLines.count && j < translationLines.count {
            let originalLine = originalLines[i]
            let translationLine = translationLines[j]
            let timeDiff = abs(
                originalLine.startTimeMS - translationLine.startTimeMS)

            if timeDiff < threshold {
                // 时间戳匹配，合并翻译
                var mergedLine = originalLine
                mergedLine.attachments[.translation()] = .plainText(
                    translationLine.words)
                merged.append(mergedLine)
                i += 1
                j += 1
            } else if originalLine.startTimeMS < translationLine.startTimeMS {
                // 原始歌词时间戳较早，添加原始歌词行
                merged.append(originalLine)
                i += 1
            } else {
                // 翻译歌词时间戳较早，跳过翻译行
                j += 1
            }
        }

        // 添加剩余的原始歌词行
        while i < originalLines.count {
            merged.append(originalLines[i])
            i += 1
        }

        return merged
    }

    private func QQLyricInit(_ description: String) {
        let lines = lyricsLineRegex.matches(in: description).flatMap { match in
            let timeTagStr = match[1]!.string
            let timeTags = resolveTimeTag(timeTagStr)

            let lyricsContentStr = match[2]!.string
            var line = LyricLine(startTime: 0, words: lyricsContentStr)

            if let translationStr = match[3]?.string, !translationStr.isEmpty {
                line.attachments[.translation()] = .plainText(translationStr)
            }

            return timeTags.map { timeTag in
                var l = line
                l.startTimeMS = timeTag * 1000
                return l
            }
        }.sorted {
            $0.startTimeMS < $1.startTimeMS
        }
        self.lyrics = lines
    }

    private func resolveTimeTag(_ str: String) -> [TimeInterval] {
        let timeTagRegex = Regex(#"\[([-+]?\d+):(\d+(?:\.\d+)?)\]"#)
        let matchs = timeTagRegex.matches(in: str)
        return matchs.map { match in
            let min = Double(match[1]!.content)!
            let sec = Double(match[2]!.content)!
            return min * 60 + sec
        }
    }
}
