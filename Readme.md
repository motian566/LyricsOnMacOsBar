# 🎵 LyricsOnMacOSBar

![Platform](https://img.shields.io/badge/Platform-macOS-lightgrey.svg)
![Swift](https://img.shields.io/badge/Swift-5.0+-orange.svg)
![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Version](https://img.shields.io/badge/Version-1.8.0-success.svg)

**LyricsOnMacOSBar** 是一款专为 macOS Apple Music 打造的轻量级菜单栏歌词插件。
采用 Swift & SwiftUI 原生开发，拥有极简的 UI 设计、多重数据源回退机制以及零延迟的播放控制体验。

本项目所有代码及 icon 均来自 **Gemini 3.1 Pro**。

本项目编译于 macOS 26.5，Minimum Deployments 版本为 macOS 15.6，仅测试 macOS 26.4 上可正常运行，未测试其他版本。

## ✨ 核心特性

- 🏠 **极简与无感**：纯粹的 Agent (UIElement) 应用，没有多余的窗口，不会在 Dock 栏显示图标，安静地常驻在菜单栏。**支持音乐暂停时自动隐藏歌词**，将对屏幕的打扰降到最低。
- 🎵 **Apple Music 官方歌词**：支持在菜单栏手动输入你的专属 `media-user-token`，直接解锁并抓取 Apple Music 的歌词，实现原生级完美卡点。
- 🔄 **多数据源智能轮询**：
  - **官方直连**：优先尝试 Apple Music 官方网络库抓取。
  - **本地优先**：支持读取本地 `.lrc` 文件，完美解决演唱会 Live 版、特殊版歌曲时间轴不匹配的强迫症痛点。
  - **网络降级**：依次通过 **网易云音乐 -> QQ 音乐 -> LRCLIB** 进行责任链搜索，大幅提高歌词命中率。
- ⚡️ **零延迟原生控制台**：
  - 集成「上一首 / 播放暂停 / 下一首」图形化多媒体控制。
  - 采用 **乐观更新 (Optimistic Update)** 与多线程异步机制，点击瞬间即刻反馈，告别系统 API 的卡顿感。
- 🎨 **高度定制化**：支持随时在菜单栏手动强制切换当前歌曲的歌词抓取源。

## 🚀 快速开始

### 方式一：直接下载运行
1. 进入本仓库的 [Releases](#) 页面。
2. 下载最新版本的 `LyricsOnMacOSBar-v1.8.0.dmg`。
3. 将 `.app` 文件拖入 `应用程序 (Applications)` 文件夹。
4. **解除系统限制**：由于个人开源项目未购买苹果开发者签名，初次运行可能会提示“软件已损坏”。请打开**终端 (Terminal)**，输入以下命令并回车：
   
   ```bash
   sudo xattr -cr /Applications/LyricsOnMacOSBar.app

### 方式二：本地编译
1. 克隆本项目：`git clone https://github.com/motian566/LyricsOnMacOSBar.git`
2. 使用 Xcode 打开 `LyricsOnMacOSBar.xcodeproj`。
3. 信任开发者证书，按 `Cmd + R` 即可编译运行。

## 📁 Apple Music 歌词使用说明

如果你是 Apple Music 的付费订阅用户，可以通过以下方式解锁官方歌词：

1. 在 Mac 浏览器登录网页版 Apple Music。
2. 按 `F12` 打开开发者工具，选择 **Network (网络)** 面板后**刷新页面**。
3. 在 **Network (网络)** 搜索 `amp-api...` ，点击任一结果（如account），选择右侧**标头**，在其中找到`请求 - media-user-token`，复制 `media-user-token` 的值。
4. 点击本软件的菜单栏图标，展开 **「Apple Music 订阅 token 设置」**，将 Token 粘贴并保存即可。

## 📁 本地歌词使用说明

如果你发现某些歌曲的网源时间轴完全对不上，你可以使用本地歌词功能：
1. 点击菜单栏歌词图标，选择 **「打开本地歌词文件夹」**（默认路径为 `~/Documents/MacLyrics`）。
2. 将准备好的 `.lrc` 歌词文件放入该文件夹中。
3. **命名规范**：`歌名 - 歌手.lrc` 或 `歌名.lrc`（注意去除多余的后缀如 (Live版)）。
4. 切换歌曲，系统将优先精准读取你的本地配置！

## 👨‍💻 开发者

- **motian566** ## ⚖️ 开源协议与致谢

本项目基于 **[MIT License](LICENSE)** 协议开源。

**【开源声明 / MIT License】** 

本软件基于 MIT 协议进行开源。你可以自由地使用、复制、修改、合并、出版发行、散布、再授权及贩售本软件及其副本，只需按协议规定保留版权声明。

**【致谢 / Acknowledgements】** 

本项目中 Apple Music 官方歌词的 获取与解析逻辑，参考并移植自基于 MIT 协议的优秀开源项目：

- **Manzana-Apple-Music-Lyrics** (作者: dropcreations)
- 项目链接：https://github.com/dropcreations/Manzana-Apple-Music-Lyrics

**【免责声明 / Disclaimer】** 

本软件按“原样”提供，不带有任何明示或暗示的担保。软件仅作个人编程学习与技术交流使用，本身不提供、不存储任何数字版权受限的音乐资源。作者对使用本软件抓取网络歌词的数据准确性、潜在的版权纠纷，以及引发的任何直接或间接后果不承担法律责任。
