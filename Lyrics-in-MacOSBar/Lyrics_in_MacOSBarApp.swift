import SwiftUI
import AppKit

@main
struct LyricsOnMacOSBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    
    let monitor = MusicMonitor.shared
    let lyricManager = LyricManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView(musicMonitor: monitor, lyricManager: lyricManager)
        )

        // 启动时只创建一次状态栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = false
        
        if let btn = statusItem.button {
            btn.action = #selector(togglePopover(_:))
            btn.target = self
            btn.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
            btn.imagePosition = .imageLeft
            // 去除了 wantsLayer，不需要做动画了
        }

        monitor.onStateChange = { [weak self] isPlaying, lyric in
            self?.updateMenuBar(isPlaying: isPlaying, lyric: lyric)
        }
    }

    func updateMenuBar(isPlaying: Bool, lyric: String) {
        if isPlaying {
            if let btn = statusItem.button {
                // 🔪 已经移除了所有动画，歌词直接赋值，做到零延迟卡点切换！
                if btn.title != lyric {
                    btn.title = lyric
                }
            }
            
            // 依然保留底层的显示机制，防止黑块和崩溃
            if !statusItem.isVisible {
                statusItem.isVisible = true
            }
        } else {
            if statusItem.isVisible {
                statusItem.isVisible = false
            }
            if popover.isShown {
                popover.performClose(nil)
            }
        }
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

// === 下方 UI 视图代码保持原样 ===
struct MenuContentView: View {
    @ObservedObject var musicMonitor: MusicMonitor
    let lyricManager: LyricManager
    
    var body: some View {
        VStack(spacing: 0) {
            Menu("当前歌词源: \(musicMonitor.selectedSource.rawValue)") {
                ForEach(LyricSourceConfig.allCases, id: \.self) { source in
                    Button(action: {
                        musicMonitor.selectedSource = source
                        musicMonitor.reFetchLyrics()
                    }) {
                        Text(musicMonitor.selectedSource == source ? "✓ \(source.rawValue)" : "   \(source.rawValue)")
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
            
            Divider()
            
            HStack(spacing: 40) {
                Button(action: { musicMonitor.previousTrack() }) {
                    Image(systemName: "backward.fill").font(.system(size: 18))
                }.buttonStyle(.plain)
                
                Button(action: { musicMonitor.togglePlayPause() }) {
                    Image(systemName: musicMonitor.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24))
                }.buttonStyle(.plain)
                
                Button(action: { musicMonitor.nextTrack() }) {
                    Image(systemName: "forward.fill").font(.system(size: 18))
                }.buttonStyle(.plain)
            }
            .padding(.vertical, 16)
            
            Divider()
            
            VStack(spacing: 4) {
                Button(action: { NSWorkspace.shared.open(lyricManager.localFolderURL) }) {
                    HStack { Text("打开本地歌词文件夹"); Spacer() }
                    .padding(.vertical, 6).padding(.horizontal, 16).contentShape(Rectangle())
                }.buttonStyle(.plain)
                
                Button(action: { showAboutWindow() }) {
                    HStack { Text("关于 LyricsOnMacOSBar"); Spacer() }
                    .padding(.vertical, 6).padding(.horizontal, 16).contentShape(Rectangle())
                }.buttonStyle(.plain)
                
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    HStack { Text("退出"); Spacer() }
                    .padding(.vertical, 6).padding(.horizontal, 16).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            .padding(.vertical, 8)
        }
        .frame(width: 260)
    }
    
    private func showAboutWindow() {
        let alert = NSAlert()
        if let appIcon = NSImage(named: "AppIcon") { alert.icon = appIcon }
        alert.messageText = "关于 LyricsOnMacOSBar"
        alert.informativeText = "开发者: motian566\n\n【开源与免费声明】\n本软件为 GitHub 上的开源免费项目，代码完全公开。严禁任何个人或组织将本软件用于商业牟利、二次打包或倒卖行为。\n仓库地址：https://github.com/motian566/LyricsOnMacOSBar\n\n【免责声明】\n本软件仅作个人编程学习与技术交流使用。软件本身不提供、不存储任何音乐资源。作者不对使用本软件抓取网络歌词的数据准确性、潜在的版权纠纷，以及由此引发的任何直接或间接损失承担法律责任。"
        alert.addButton(withTitle: "我知道了")
        alert.addButton(withTitle: "访问 GitHub 主页")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            if let url = URL(string: "https://github.com/motian566/LyricsOnMacOSBar") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
