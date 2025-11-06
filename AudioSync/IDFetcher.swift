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

// MARK: - 2. 导航辅助枚举
public enum IDFetchError: Error, LocalizedError {
    case networkError(Error)
    case dataParsingError
    case artistNotFound
    case invalidURL
    
    public var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "网络请求失败: \(error.localizedDescription)"
        case .dataParsingError:
            return "数据解析失败，JSON结构可能已更改。"
        case .artistNotFound:
            return "未找到匹配的艺术家 ID。"
        case .invalidURL:
            return "URL 构造失败。"
        }
    }
}

// MARK: - 3. ID 获取器
public enum IDFetcher {

    /**
     根据艺术家的名字，异步获取其 iTunes Search API 的 Artist ID。
     
     这是一个公共 API，不需要付费的 Apple 开发者账户或 API Key。

     - Parameter name: 艺术家的名字 (例如 "Stevie Wonder")。
     - Parameter countryCode: 商店代码，如 "cn" (中国), "us" (美国)。默认为 "cn"。
     - Returns: 艺术家的 ID 字符串 (例如 "159260351")。
     - Throws: 遇到网络或解析错误时抛出 `IDFetchError`。
     */
    public static func fetchArtistID(
        by name: String,
        countryCode: String = "cn"
    ) async throws -> String {
        
        // 1. URL 构造
        let baseURL = "https://itunes.apple.com/search"
        
        // 对名字进行 URL 编码，以处理空格和特殊字符
        guard let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw IDFetchError.invalidURL
        }
        
        // 设置搜索参数: term=艺术家名字, entity=allArtist, media=music, limit=1
        let urlString = "\(baseURL)?term=\(encodedName)&entity=allArtist&media=music&limit=1&country=\(countryCode)"

        guard let url = URL(string: urlString) else {
            throw IDFetchError.invalidURL
        }

        print("正在查询 iTunes Search API: \(url.absoluteString)")

        // 2. 网络请求
        let (data, _) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            // 使用 URLSession 发起请求
            let task = URLSession.shared.dataTask(with: url) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: IDFetchError.networkError(error))
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
            let searchResult = try decoder.decode(ArtistSearchResult.self, from: data)
            
            guard let firstArtist = searchResult.results.first else {
                throw IDFetchError.artistNotFound
            }
            
            let artistId = String(firstArtist.artistId)
            print("找到 ID: \(artistId) for \(firstArtist.artistName)")
            return artistId
            
        } catch {
            // 可能是 JSON 解码错误或艺术家未找到
            if error is IDFetchError {
                throw error
            }
            throw IDFetchError.dataParsingError
        }
    }
}

// --- 完整的调用流程示例 (结合 MusicNavigator) ---
/*
// 假设你有一个按钮点击事件或任务启动点：
func handleArtistNavigation(artistName: String) {
    Task {
        do {
            // 步骤 1: 根据名字获取 ID
            let artistID = try await IDFetcher.fetchArtistID(by: artistName)
            
            // 步骤 2: 使用 ID 跳转到艺术家主页 (使用 Universal Link，如 MusicNavigator 中所推荐)
            let success = try MusicNavigator.openArtistPage(by: artistID, storefrontCode: "cn")
            
            if success {
                print("成功打开 Apple Music 艺术家主页。")
            } else {
                print("无法打开 Apple Music App (App 未安装或系统权限问题)。")
            }
            
        } catch {
            // 如果获取 ID 失败，回退到 AppleScript 搜索 (方案 2)
            if let fetchError = error as? IDFetchError, case .artistNotFound = fetchError {
                print("ID 未找到，回退到 AppleScript 搜索...")
                try? MusicNavigator.searchMusicStore(for: artistName)
            } else {
                print("导航失败: \(error.localizedDescription)")
            }
        }
    }
}

// 示例调用：
// handleArtistNavigation(artistName: "Taylor Swift")
*/
