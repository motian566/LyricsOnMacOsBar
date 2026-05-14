import Foundation
import Combine
import AppKit

class MusicMonitor: ObservableObject {
    static let shared = MusicMonitor()
    
    @Published var currentLyricLine: String = "等待播放..." {
        didSet { notifyAppKit() }
    }
    @Published var selectedSource: LyricSourceConfig = .auto
    @Published var isPlaying: Bool = false {
        didSet { notifyAppKit() }
    }
    
    var onStateChange: ((Bool, String) -> Void)?
    
    private var currentTrackName: String = ""
    private var currentArtistName: String = ""
    private var currentLyrics: [ParsedLyricLine] = []
    private let lyricManager = LyricManager()
    
    // ⚠️ 核心重构：双定时器机制
    private var syncTimer: Timer? // 负责后台与 Apple Music 低频同步
    private var uiTimer: Timer?   // 负责本地高频推算和刷新 UI
    
    // 记录时间插值需要的基准数据
    private var lastKnownPosition: Double = 0.0
    private var lastSyncTimestamp: TimeInterval = 0.0
    
    private var isFetching = false
    private let scriptQueue = DispatchQueue(label: "com.motian.lyric.script", qos: .utility)
    
    private init() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.startMonitoring()
        }
    }
    
    private func notifyAppKit() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onStateChange?(self.isPlaying, self.currentLyricLine)
        }
    }
    
    func startMonitoring() {
        // 1. 同步定时器：每 1 秒在后台悄悄问一次 Apple Music（彻底解放 CPU）
        syncTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.fetchCurrentTrackInfo()
        }
        RunLoop.main.add(syncTimer!, forMode: .common)
        
        // 2. UI 渲染定时器：每 0.1 秒推算一次当前精确时间，做到极致卡点
        uiTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tickUI()
        }
        RunLoop.main.add(uiTimer!, forMode: .common)
    }
    
    // 本地时间推算逻辑
    private func tickUI() {
        guard isPlaying else { return } // 没播放时停止推算
        
        // 核心算法：当前系统时间 - 上次同步的系统时间 = 经过的时间。
        // 将经过的时间加上上次音乐的时间，得出极其精准的当前播放毫秒级时间。
        let elapsedSinceSync = Date().timeIntervalSince1970 - lastSyncTimestamp
        let estimatedTime = lastKnownPosition + elapsedSinceSync
        
        updateLyric(for: estimatedTime)
    }
    
    func fetchCurrentTrackInfo() {
        guard !isFetching else { return }
        isFetching = true
        
        scriptQueue.async {
            let script = """
            if application "Music" is running then
                tell application "Music"
                    try
                        if player state is playing then
                            return "Playing|||" & (name of current track) & "|||" & (artist of current track) & "|||" & (player position)
                        else
                            return "Paused"
                        end if
                    on error
                        return "Error"
                    end try
                end tell
            end if
            return "Stopped"
            """
            
            var error: NSDictionary?
            let res = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue ?? "Stopped"
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.handleResult(res)
                self.isFetching = false
            }
        }
    }
    
    private func handleResult(_ res: String) {
        if res == "Stopped" || res == "Paused" || res == "Error" {
            if self.isPlaying { self.isPlaying = false }
            return
        }
        
        let parts = res.components(separatedBy: "|||")
        if parts.count == 4 {
            let name = parts[1]
            let artist = parts[2]
            let time = Double(parts[3]) ?? 0.0
            
            if !self.isPlaying { self.isPlaying = true }
            
            // ⚠️ 重点：每次拿到真实时间后，重置本地推算的基准！
            self.lastKnownPosition = time
            self.lastSyncTimestamp = Date().timeIntervalSince1970
            
            if name != self.currentTrackName || artist != self.currentArtistName {
                self.currentTrackName = name
                self.currentArtistName = artist
                self.reFetchLyrics()
            } else {
                self.updateLyric(for: time)
            }
        }
    }
    
    func reFetchLyrics() {
        guard !currentTrackName.isEmpty, !currentArtistName.isEmpty else { return }
        self.currentLyricLine = "获取歌词中..."
        
        Task {
            let fetchedLyrics = await self.lyricManager.fetchLyrics(
                trackName: self.currentTrackName,
                artistName: self.currentArtistName,
                sourceConfig: self.selectedSource
            ) { statusText in
                DispatchQueue.main.async {
                    if self.currentLyricLine != statusText { self.currentLyricLine = statusText }
                }
            }
            
            DispatchQueue.main.async {
                self.currentLyrics = fetchedLyrics
                if fetchedLyrics.isEmpty {
                    let fallbackText = "\(self.currentTrackName) (未找到歌词)"
                    if self.currentLyricLine != fallbackText { self.currentLyricLine = fallbackText }
                }
            }
        }
    }
    
    private func updateLyric(for time: Double) {
        guard !currentLyrics.isEmpty else { return }
        // 使用刚刚推算出的高精度时间来匹配歌词
        if let matchedLine = currentLyrics.reversed().first(where: { $0.time <= time }) {
            if self.currentLyricLine != matchedLine.text {
                self.currentLyricLine = matchedLine.text
            }
        }
    }
    
    func togglePlayPause() {
        scriptQueue.async {
            NSAppleScript(source: "tell application \"Music\" to playpause")?.executeAndReturnError(nil)
        }
    }
    
    func previousTrack() {
        DispatchQueue.main.async { self.currentLyricLine = "切换中..." }
        scriptQueue.async {
            NSAppleScript(source: "tell application \"Music\" to previous track")?.executeAndReturnError(nil)
        }
    }
    
    func nextTrack() {
        DispatchQueue.main.async { self.currentLyricLine = "切换中..." }
        scriptQueue.async {
            NSAppleScript(source: "tell application \"Music\" to next track")?.executeAndReturnError(nil)
        }
    }
}
