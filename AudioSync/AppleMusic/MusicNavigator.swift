import AppKit  // 用于 NSWorkspace
import Foundation

/// 封装了与 Apple Music App 交互的导航功能。
public enum MusicNavigator {

    /// 错误类型
    public enum NavigationError: Error {
        case appleScriptError(String)
        case invalidURL
    }
    /**
     使用 URL Scheme 直接打开一位艺术家的 Apple Music 主页。
    
     - Parameter artistID: 艺术家的数字 ID。
     - Throws: 如果 URL 构造失败，则抛出 `NavigationError.invalidURL`。
     - Returns: Bool - `NSWorkspace` 的 `open` 函数的返回值。
     */
    public static func openArtistPage(
        by artistID: String,
        storefrontCode: String = "cn"
    ) throws -> Bool {

        // 构建 Universal Link (HTTPS)
        // 使用占位符 'artist-name'，因为 OS 主要是看 ID
        // '?app=music' 是一个很好的提示，确保系统调用 Music App
        let urlString =
            "https://music.apple.com/\(storefrontCode)/artist/\(artistID)?app=music"

        guard let url = URL(string: urlString) else {
            Log.backend.error("错误: 无法构造 URL: \(urlString)")
            throw NavigationError.invalidURL
        }

        print("正在尝试打开 Universal Link: \(url.absoluteString)")

        // NSWorkspace 负责将这个 HTTPS 链接识别为 Universal Link，并打开 Music.app
        return NSWorkspace.shared.open(url)
    }
}
