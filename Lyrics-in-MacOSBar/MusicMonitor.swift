import Foundation
import Combine
import AppKit

class MusicMonitor: ObservableObject {
    static let shared = MusicMonitor()
    
    @Published var currentLyricLine: String = "开始听歌！" {
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
    private let lyricManager = LyricManager.shared
    
    private var syncTimer: Timer?
    private var uiTimer: Timer?
    
    private var lastKnownPosition: Double = 0.0
    private var lastSyncTimestamp: TimeInterval = 0.0
    private var currentDuration: Double = 0.0
    
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
        syncTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.fetchCurrentTrackInfo()
        }
        RunLoop.main.add(syncTimer!, forMode: .common)
        
        uiTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tickUI()
        }
        RunLoop.main.add(uiTimer!, forMode: .common)
    }
    
    private func tickUI() {
        guard isPlaying else { return }
        let elapsedSinceSync = Date().timeIntervalSince1970 - lastSyncTimestamp
        let estimatedTime = lastKnownPosition + elapsedSinceSync
        updateLyric(for: estimatedTime)
    }
    
    private func executeAppleScript(_ script: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Stopped"
        } catch {
            return "Error"
        }
    }
    
    private func executeAppleScriptAction(_ script: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
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
                            return "Playing|||" & (name of current track) & "|||" & (artist of current track) & "|||" & (player position) & "|||" & (duration of current track)
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
            
            let res = self.executeAppleScript(script)
            
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
        if parts.count >= 4 {
            let name = parts[1]
            let artist = parts[2]
            let time = Double(parts[3]) ?? 0.0
            
            let duration = parts.count == 5 ? (Double(parts[4]) ?? 0.0) : 0.0
            
            if !self.isPlaying { self.isPlaying = true }
            
            self.lastKnownPosition = time
            self.lastSyncTimestamp = Date().timeIntervalSince1970
            
            if name != self.currentTrackName || artist != self.currentArtistName {
                self.currentTrackName = name
                self.currentArtistName = artist
                self.currentDuration = duration
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
                duration: self.currentDuration,
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
                } else {
                    // ⚠️ 修复 1：歌词获取完毕后，强制立即刷新一次 UI。
                    // 这样就能立刻把“正在请求...”清空，渲染当前的真实状态
                    self.updateLyric(for: self.lastKnownPosition)
                }
            }
        }
    }
    
    private func updateLyric(for time: Double) {
        guard !currentLyrics.isEmpty else { return }
        
        if let matchedLine = currentLyrics.reversed().first(where: { $0.time <= time }) {
            if self.currentLyricLine != matchedLine.text {
                self.currentLyricLine = matchedLine.text
            }
        } else {
            // ⚠️ 修复 2：当前时间比第一句歌词还要早（前奏期间，或进度条被拉回开头）
            // 此时不该卡住，而是显示歌曲名信息
            let introText = "\(currentTrackName) - \(currentArtistName)"
            if self.currentLyricLine != introText {
                self.currentLyricLine = introText
            }
        }
    }
    
    func togglePlayPause() {
        scriptQueue.async { self.executeAppleScriptAction("tell application \"Music\" to playpause") }
    }
    
    func previousTrack() {
        DispatchQueue.main.async { self.currentLyricLine = "切换中..." }
        scriptQueue.async { self.executeAppleScriptAction("tell application \"Music\" to previous track") }
    }
    
    func nextTrack() {
        DispatchQueue.main.async { self.currentLyricLine = "切换中..." }
        scriptQueue.async { self.executeAppleScriptAction("tell application \"Music\" to next track") }
    }
}
