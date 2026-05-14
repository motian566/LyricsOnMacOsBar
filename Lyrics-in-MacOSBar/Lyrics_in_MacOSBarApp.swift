//
//  LyricsOnMacOSBarApp.swift
//  Lyrics-in-MacOSBar
//
//  Created by 何旺霖 on 2026/5/14.
//


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
    
    var eventMonitor: Any?

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
    
    // ⚠️ 核心修复：分离出单独的 Show 方法
        func showPopover(sender: AnyObject?) {
            guard let button = statusItem.button else { return }
            
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            
            // 1. 强行把咱们的后台 App 提权到前台活跃状态，以便接收系统事件
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
            
            // 2. 埋下全局鼠标监听雷达。只要在屏幕任何地方点了左/右键，强行关闭窗口
            if eventMonitor == nil {
                eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    if let popover = self?.popover, popover.isShown {
                        self?.closePopover(sender: event)
                    }
                }
            }
        }
        
        // ⚠️ 核心修复：分离出单独的 Close 方法
        func closePopover(sender: AnyObject?) {
            popover.performClose(sender)
            
            // 窗口关掉后，一定要把监听器拆除，否则会造成内存泄漏，导致电脑越用越卡
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
    }



// === 下方 UI 视图代码保持原样 ===
struct MenuContentView: View {
    @ObservedObject var musicMonitor: MusicMonitor
    let lyricManager: LyricManager
    
    @State private var inputToken: String = UserDefaults.standard.string(forKey: "AppleMusicMediaUserToken") ?? ""
    @State private var showSettings: Bool = false
    
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
            
            // ⚠️ 新增：Token 设置区域
            VStack(alignment: .leading, spacing: 8) {
                            // 1. 去掉 withAnimation，让展开动作瞬间完成
                            Button(action: { showSettings.toggle() }) {
                                HStack {
                                    Text("Apple Music 订阅 token 设置")
                                    Spacer()
                                    // 2. 将动画仅作用于右侧箭头图标的旋转上
                                    Image(systemName: showSettings ? "chevron.up" : "chevron.down")
                                                                .font(.system(size: 13, weight: .semibold)) // 固定字重和大小
                                                                .frame(width: 16, alignment: .center)
                                                                // 取消所有绑定在这个图标上的动画
                                                                .animation(nil, value: showSettings)
                                                        }
                                .padding(.vertical, 6).padding(.horizontal, 16).contentShape(Rectangle())
                            }.buttonStyle(.plain)

                            if showSettings {
                                VStack(spacing: 10) {
                                    Text("请输入 media-user-token 以获取官方歌词：")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    TextField("粘贴 Token 到这里...", text: $inputToken)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11))
                                    
                                    Button(action: {
                                        UserDefaults.standard.set(inputToken, forKey: "AppleMusicMediaUserToken")
                                        musicMonitor.reFetchLyrics()
                                        
                                        let haptic = NSHapticFeedbackManager.defaultPerformer
                                        haptic.perform(.generic, performanceTime: .now)
                                        
                                        // 3. 去掉 withAnimation，瞬间收起
                                        showSettings = false
                                    }) {
                                        Text("保存并应用")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                            }
                        }
            
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
        alert.informativeText = """
                版本 / Version: 1.8.0
                开发者 / Developer: motian566
                邮箱 / Email: h894734566@163.com
                
                【开源声明 / MIT License】
                本软件为基于 MIT 协议进行开源。你可以自由地使用、复制、修改、合并、出版发行、散布、再授权及贩售本软件及其副本，只需按协议规定保留版权声明。
                仓库地址：https://github.com/motian566/LyricsOnMacOSBar
                
                【致谢 / Acknowledgements】
                Apple Music 官方歌词的 API 获取与解析逻辑，翻译/移植自基于 MIT 协议的开源项目：
                Manzana-Apple-Music-Lyrics (作者: dropcreations)
                https://github.com/dropcreations/Manzana-Apple-Music-Lyrics
                
                【免责声明 / Disclaimer】
                本软件仅作个人编程学习与技术交流使用。软件本身不提供、不存储任何音乐资源。作者不对使用本软件抓取网络歌词的数据准确性、潜在的版权纠纷，以及由此引发的任何直接或间接损失承担法律责任。
                """
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
