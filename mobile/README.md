# Cloud CLI Mobile

Cloud CLI（Claude Code UI）的 iPhone 客户端。聊天页是原生 Flutter（流式输出、工具调用卡、授权、会话目录跳转、分页翻历史），终端/文件/Git/Task Master 等用内嵌网页版兜底。

设计文档：`../docs/superpowers/specs/2026-09-21-cloudcli-mobile-flutter-design.md`

## 环境

- Flutter 3.38+（Dart 3.10+）、Xcode 26+、CocoaPods
- 真机需要 iOS 13+；免费签名 7 天过期

## 跑起来

```bash
flutter pub get
flutter run                     # 选模拟器或真机
flutter analyze && flutter test  # 提交前跑
```

## 连哪台服务器

登录页填「服务器地址 + 用户名 + 密码」，账号就是服务器上网页版的账号（在网页版首次注册）。

| 场景 | 地址填什么 |
| --- | --- |
| 模拟器连本机服务 | `127.0.0.1:3001` |
| 手机连本机服务（同一 Wi-Fi） | 本机局域网 IP，如 `172.18.239.130:3001`（`ipconfig getifaddr en0`） |
| 手机连 VPS | `你的域名或 IP:端口` |

自托管通常是明文 HTTP，`ios/Runner/Info.plist` 已放开 ATS（`NSAllowsArbitraryLoads`）并声明了本地网络权限（`NSLocalNetworkUsageDescription`），否则 iOS 会直接拒绝连接。

## 装到 iPhone（自用，不上架）

1. `open ios/Runner.xcworkspace`
2. Runner → Signing & Capabilities → 勾选 Automatically manage signing，选你的 Apple ID（免费即可）
3. Bundle Identifier 改成唯一值（如 `ai.cloudcli.<你的名字>Mobile`）
4. 插上 iPhone，在设备里信任开发者证书；iOS 16+ 还要在「设置 → 隐私与安全性 → 开发者模式」打开 Developer Mode
5. Xcode 里选中你的手机 → Run

免费账号签的 App 7 天后打不开，重新 Run 一次即可。

## 代码结构

```text
lib/
  app/          主题 tokens、App 壳（三 tab）、登录态分流
  core/         api（dio + X-Refreshed-Token + 401）、storage（Keychain/prefs）、models、util
  features/     auth（登录）、sessions（会话列表）、settings（设置）
                chat（原生聊天，M3 起）、workspace（网页兜底，M5 起）
```

约定：`features/*` 依赖 `core/*`，`core` 不反向依赖；UI 不直接碰 `dio` / `web_socket_channel`。
