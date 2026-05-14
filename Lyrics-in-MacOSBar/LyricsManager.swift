import Foundation
import AppKit

enum LyricSourceConfig: String, CaseIterable {
    case auto = "自动匹配 (推荐)"
    case appleMusicWeb = "Apple Music 官方歌词"
    case local = "本地歌词文件"
    case netease = "网易云音乐"
    case qq = "QQ 音乐"
    case lrclib = "LRCLIB"
}

// === Apple Music Web API 模型 ===
struct AMWebSearchResponse: Codable { let results: AMWebSearchResults? }
struct AMWebSearchResults: Codable { let songs: AMWebSongData? }
struct AMWebSongData: Codable { let data: [AMWebSong]? }
struct AMWebSong: Codable {
    let id: String
    let attributes: AMWebSongAttributes?
}
struct AMWebSongAttributes: Codable { let durationInMillis: Int? }

struct AMWebLyricResponse: Codable { let data: [AMWebLyricSong]? }
struct AMWebLyricSong: Codable { let relationships: AMWebRelationships? }
struct AMWebRelationships: Codable {
    let lyrics: AMWebLyricsData?
    let syllableLyrics: AMWebLyricsData? // 包含逐字歌词
    
    enum CodingKeys: String, CodingKey {
        case lyrics
        case syllableLyrics = "syllable-lyrics"
    }
}
struct AMWebLyricsData: Codable { let data: [AMWebLyricsItem]? }
struct AMWebLyricsItem: Codable { let attributes: AMWebLyricsAttributes? }
struct AMWebLyricsAttributes: Codable { let ttml: String? }

// === 其他数据源模型 ===
struct NeteaseSearchResponse: Codable { let result: NeteaseSearchResult? }
struct NeteaseSearchResult: Codable { let songs: [NeteaseSong]? }
struct NeteaseSong: Codable { let id: Int; let dt: Int }
struct NeteaseLyricResponse: Codable { let lrc: NeteaseLrc? }
struct NeteaseLrc: Codable { let lyric: String? }

struct LRCLibResponse: Codable { let syncedLyrics: String? }

struct QQSearchResponse: Codable { let data: QQSearchData? }
struct QQSearchData: Codable { let song: QQSongList? }
struct QQSongList: Codable { let list: [QQSong]? }
struct QQSong: Codable { let songmid: String }
struct QQLyricResponse: Codable { let lyric: String? }

struct ParsedLyricLine {
    let time: TimeInterval
    let text: String
}

class LyricManager {
    static let shared = LyricManager()
    
    // 缓存 JWT Token
    private var cachedAppleMusicToken: String? = nil
    
    // ⚠️ 你的专属 Apple Music 会员凭证
    private var myMediaUserToken: String {
            return UserDefaults.standard.string(forKey: "AppleMusicMediaUserToken") ?? ""
        }
    
    private let browserUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36"
    
    var localFolderURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("MacLyrics")
    }
    
    init() {
            if !FileManager.default.fileExists(atPath: localFolderURL.path) {
                try? FileManager.default.createDirectory(at: localFolderURL, withIntermediateDirectories: true)
            }
            print("[AM_DEBUG] 当前加载的 Token 长度: \(myMediaUserToken.count)")
        }
    
    // 统一配置苹果 API 请求头
    private func applyHeaders(to request: inout URLRequest, withToken token: String? = nil) {
        request.setValue("application/json;charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.apple.com/", forHTTPHeaderField: "Referer")
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        
        // 注入基础访问 Token
        if let t = token {
            request.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        
        // 注入高权限会员 Token
        if !myMediaUserToken.isEmpty {
            request.setValue(myMediaUserToken, forHTTPHeaderField: "media-user-token")
        }
    }
    
    func fetchLyrics(trackName: String, artistName: String, duration: Double, sourceConfig: LyricSourceConfig, onStatusUpdate: @escaping (String) -> Void) async -> [ParsedLyricLine] {
        let cleanTrack = cleanText(trackName)
        let cleanArtist = cleanText(artistName)
        
        // 1. Apple Music 官方直连 (最高优先级)
        if sourceConfig == .auto || sourceConfig == .appleMusicWeb {
            onStatusUpdate(sourceConfig == .auto ? "尝试 Apple Music 官方网络库..." : "正在请求 Apple Music...")
            let webResult = await fetchFromAppleMusicWeb(track: cleanTrack, artist: cleanArtist, expectedDuration: duration)
            if !webResult.isEmpty { return webResult }
            if sourceConfig == .appleMusicWeb { return [] }
        }
        
        
        // 2. 本地文件优先策略
        if sourceConfig == .auto || sourceConfig == .local {
            onStatusUpdate("匹配本地文件...")
            let localResult = fetchFromLocal(track: cleanTrack, artist: cleanArtist)
            if !localResult.isEmpty { return localResult }
            if sourceConfig == .local { return [] }
        }
        
        // 3. 网络备用源
        if sourceConfig == .auto || sourceConfig == .netease {
            onStatusUpdate("搜索网易云...")
            let neteaseResult = await fetchFromNetease(track: cleanTrack, artist: cleanArtist, expectedDuration: duration)
            if !neteaseResult.isEmpty { return neteaseResult }
            if sourceConfig == .netease { return [] }
        }
        
        if sourceConfig == .auto || sourceConfig == .qq {
            onStatusUpdate("搜索 QQ 音乐...")
            let qqResult = await fetchFromQQMusic(track: cleanTrack, artist: cleanArtist)
            if !qqResult.isEmpty { return qqResult }
            if sourceConfig == .qq { return [] }
        }
        
        if sourceConfig == .auto || sourceConfig == .lrclib {
            onStatusUpdate("搜索 LRCLIB...")
            let lrclibResult = await fetchFromLRCLib(track: cleanTrack, artist: cleanArtist, expectedDuration: duration)
            if !lrclibResult.isEmpty { return lrclibResult }
            if sourceConfig == .lrclib { return [] }
        }
        
        return []
    }
    
    // === 🎵 Apple Music 官方核心爬虫 ===
    private func fetchFromAppleMusicWeb(track: String, artist: String, expectedDuration: Double) async -> [ParsedLyricLine] {
        guard let token = await getAppleMusicToken() else { return [] }
        
        let keyword = "\(track) \(artist)"
        guard let encodedKeyword = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        
        let storefronts = ["cn", "us", "jp"]
        for sf in storefronts {
            let searchUrl = URL(string: "https://amp-api.music.apple.com/v1/catalog/\(sf)/search?types=songs&term=\(encodedKeyword)&limit=10&l=zh-CN")!
            var request = URLRequest(url: searchUrl)
            applyHeaders(to: &request, withToken: token)
            
            do {
                let (searchData, searchResp) = try await URLSession.shared.data(for: request)
                guard let httpResp = searchResp as? HTTPURLResponse, httpResp.statusCode == 200 else { continue }
                
                let searchResponse = try JSONDecoder().decode(AMWebSearchResponse.self, from: searchData)
                guard let songs = searchResponse.results?.songs?.data, !songs.isEmpty else { continue }
                
                var targetId: String? = nil
                if expectedDuration > 0 {
                    for song in songs {
                        if let ms = song.attributes?.durationInMillis {
                            let diff = abs(Double(ms)/1000.0 - expectedDuration)
                            if diff <= 4.0 {
                                targetId = song.id
                                print("[AM_DEBUG] [时长匹配] 命中地区 \(sf) 版本 ID: \(song.id), 误差: \(diff) 秒")
                                break
                            }
                        }
                    }
                }
                
                let finalId = targetId ?? songs.first?.id
                if let id = finalId {
                    // ⚠️ 精准 URL 参数：请求包含完整歌词及逐字歌词
                    let lyricUrl = URL(string: "https://amp-api.music.apple.com/v1/catalog/\(sf)/songs/\(id)?include%5Bsongs%5D=albums%2Clyrics%2Csyllable-lyrics&l=zh-CN")!
                    var lyricReq = URLRequest(url: lyricUrl)
                    applyHeaders(to: &lyricReq, withToken: token)
                    
                    let (lyricData, lyricResp) = try await URLSession.shared.data(for: lyricReq)
                    guard let lHttpResp = lyricResp as? HTTPURLResponse, lHttpResp.statusCode == 200 else { continue }
                    
                    let lyricResponse = try JSONDecoder().decode(AMWebLyricResponse.self, from: lyricData)
                    
                    // 检查双重节点，优先获取 syllableLyrics
                    let relationships = lyricResponse.data?.first?.relationships
                    let ttml = relationships?.syllableLyrics?.data?.first?.attributes?.ttml ?? relationships?.lyrics?.data?.first?.attributes?.ttml
                    
                    if let ttml = ttml {
                        print("[AM_DEBUG] 身份验证通过，成功提取 VIP 动态歌词时间轴！")
                        let parsed = parseTTML(ttml)
                        if !parsed.isEmpty { return parsed }
                    } else {
                        print("[AM_DEBUG] 该版本 (\(id)) 本身不包含动态时间轴")
                    }
                }
            } catch {
                print("[AM_DEBUG] 通信链路异常: \(error.localizedDescription)")
            }
        }
        return []
    }
    
    private func getAppleMusicToken() async -> String? {
        if let cached = cachedAppleMusicToken { return cached }
        
        do {
            let url = URL(string: "https://music.apple.com/us/browse")!
            var request = URLRequest(url: url)
            applyHeaders(to: &request)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            
            let indexRegex = try NSRegularExpression(pattern: "index(.*?)\\.js\"")
            guard let indexMatch = indexRegex.firstMatch(in: html, range: NSRange(location: 0, length: html.utf16.count)) else { return nil }
            let indexHash = (html as NSString).substring(with: indexMatch.range(at:1))
            
            guard let jsUrl = URL(string: "https://music.apple.com/assets/index\(indexHash).js") else { return nil }
            var jsReq = URLRequest(url: jsUrl)
            applyHeaders(to: &jsReq)
            
            let (jsData, _) = try await URLSession.shared.data(for: jsReq)
            guard let jsText = String(data: jsData, encoding: .utf8) else { return nil }
            
            let tokenRegex = try NSRegularExpression(pattern: "(eyJh[^\"]+)")
            guard let tokenMatch = tokenRegex.firstMatch(in: jsText, range: NSRange(location: 0, length: jsText.utf16.count)) else { return nil }
            
            let token = (jsText as NSString).substring(with: tokenMatch.range(at:1))
            self.cachedAppleMusicToken = token
            return token
            
        } catch { return nil }
    }
    
    private func parseTTML(_ ttml: String) -> [ParsedLyricLine] {
        var result: [ParsedLyricLine] = []
        let pattern = "<p[^>]*begin=\"([^\"]+)\"[^>]*>(.*?)</p>"
        let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
        
        let nsTtml = ttml as NSString
        let matches = regex?.matches(in: ttml, range: NSRange(location: 0, length: nsTtml.length)) ?? []
        
        for match in matches {
            let timeStr = nsTtml.substring(with: match.range(at: 1)).replacingOccurrences(of: "s", with: "")
            let content = nsTtml.substring(with: match.range(at: 2))
            
            // 清理标签，保留纯净文本
            let text = content.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&apos;", with: "'")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
            
            if text.isEmpty { continue }
            
            let simplifiedText = text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? text
            
            let parts = timeStr.components(separatedBy: ":")
            var seconds: Double = 0
            if parts.count == 2 {
                seconds = (Double(parts[0]) ?? 0) * 60 + (Double(parts[1]) ?? 0)
            } else {
                seconds = Double(parts[0]) ?? 0
            }
            
            result.append(ParsedLyricLine(time: seconds, text: simplifiedText))
        }
        return result
    }

    private func fetchFromAppleMusicLocal() -> [ParsedLyricLine] {
        let script = "tell application \"Music\" to get lyrics of current track"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let res = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if res != "Stopped" && res != "Error" && !res.isEmpty {
            return parseLRC(res)
        }
        return []
    }
    
    private func fetchFromLocal(track: String, artist: String) -> [ParsedLyricLine] {
        let possibleNames = ["\(track) - \(artist).lrc", "\(track).lrc"]
        for fileName in possibleNames {
            let fileURL = localFolderURL.appendingPathComponent(fileName)
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                return parseLRC(content)
            }
        }
        return []
    }
    
    private func fetchFromNetease(track: String, artist: String, expectedDuration: Double) async -> [ParsedLyricLine] {
        let keyword = "\(track) \(artist)"
        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://music.163.com/api/search/get/web?s=\(encoded)&type=1&limit=10") else { return [] }
        do {
            var request = URLRequest(url: url)
            request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            let resp = try JSONDecoder().decode(NeteaseSearchResponse.self, from: data)
            if let songs = resp.result?.songs {
                let id = songs.first(where: { abs(Double($0.dt)/1000.0 - expectedDuration) < 4.0 })?.id ?? songs.first?.id
                if let songId = id {
                    let lUrl = URL(string: "https://music.163.com/api/song/lyric?id=\(songId)&lv=1")!
                    var lReq = URLRequest(url: lUrl)
                    lReq.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
                    let (lData, _) = try await URLSession.shared.data(for: lReq)
                    let lResp = try JSONDecoder().decode(NeteaseLyricResponse.self, from: lData)
                    if let lrc = lResp.lrc?.lyric { return parseLRC(lrc) }
                }
            }
        } catch { }
        return []
    }
    
    private func fetchFromQQMusic(track: String, artist: String) async -> [ParsedLyricLine] {
        let keyword = "\(track) \(artist)"
        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://c.y.qq.com/soso/fcgi-bin/client_search_cp?p=1&n=1&w=\(encoded)&format=json") else { return [] }
        do {
            var req = URLRequest(url: url)
            req.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: req)
            let resp = try JSONDecoder().decode(QQSearchResponse.self, from: data)
            if let songmid = resp.data?.song?.list?.first?.songmid {
                let lUrl = URL(string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=\(songmid)&format=json")!
                var lReq = URLRequest(url: lUrl)
                lReq.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
                lReq.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
                let (lData, _) = try await URLSession.shared.data(for: lReq)
                let lResp = try JSONDecoder().decode(QQLyricResponse.self, from: lData)
                if let base64 = lResp.lyric, let dec = Data(base64Encoded: base64),
                   var lrc = String(data: dec, encoding: .utf8) {
                    lrc = lrc.replacingOccurrences(of: "&#58;", with: ":").replacingOccurrences(of: "&#46;", with: ".").replacingOccurrences(of: "&#10;", with: "\n")
                    return parseLRC(lrc)
                }
            }
        } catch { }
        return []
    }
    
    private func fetchFromLRCLib(track: String, artist: String, expectedDuration: Double) async -> [ParsedLyricLine] {
        guard let t = track.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let a = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        var urlStr = "https://lrclib.net/api/get?track_name=\(t)&artist_name=\(a)"
        if expectedDuration > 0 { urlStr += "&duration=\(Int(expectedDuration))" }
        guard let url = URL(string: urlStr) else { return [] }
        do {
            var req = URLRequest(url: url)
            req.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: req)
            let resp = try JSONDecoder().decode(LRCLibResponse.self, from: data)
            if let synced = resp.syncedLyrics { return parseLRC(synced) }
        } catch { }
        return []
    }

    private func cleanText(_ text: String) -> String {
        var res = text.replacingOccurrences(of: "\\(.*?\\)", with: "", options: .regularExpression)
        res = res.replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression)
        if let range = res.range(of: " - ") { res = String(res[..<range.lowerBound]) }
        return res.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func parseLRC(_ lrc: String) -> [ParsedLyricLine] {
        var res: [ParsedLyricLine] = []
        let pattern = "\\[(\\d{2}):(\\d{2})\\.(\\d{2,3})\\](.*)"
        let regex = try? NSRegularExpression(pattern: pattern)
        lrc.components(separatedBy: .newlines).forEach { line in
            let ns = line as NSString
            if let match = regex?.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                let m = Double(ns.substring(with: match.range(at:1))) ?? 0
                let s = Double(ns.substring(with: match.range(at:2))) ?? 0
                let ms = Double(ns.substring(with: match.range(at:3))) ?? 0
                let t = ns.substring(with: match.range(at:4)).trimmingCharacters(in: .whitespaces)
                let time = m * 60 + s + (ms / (ns.substring(with: match.range(at:3)).count == 2 ? 100 : 1000))
                if !t.isEmpty {
                    let simplifiedText = t.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? t
                    res.append(ParsedLyricLine(time: time, text: simplifiedText))
                }
            }
        }
        return res
    }
}
