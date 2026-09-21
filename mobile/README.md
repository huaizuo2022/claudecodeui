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

## 免登录（个人构建的默认形态）

App 不应该有任何登录步骤。`run-local.sh` 会把一对「服务器地址 + 长期 token」烧进二进制：

```bash
cd mobile
./scripts/mint-seed-token.sh          # 用你本机服务器自己的 JWT 密钥签一个 365 天的 token
# 写入 mobile/.env.local（已被 git 忽略）：
#   CLOUDCLI_SERVER_URL=https://claude.huaizuo2029.cn
#   CLOUDCLI_TOKEN=<上面命令的输出>
./run-local.sh run -d <device>        # 或 ./run-local.sh build ios --simulator
```

启动顺序：Keychain 里的 token → 记住的账号密码 → **烧进二进制的种子 token** → 配置页。也就是说只要带种子构建，打开就是首页；token 平时随使用自动续期，种子在一年内永远能兜底重进。

什么时候需要重新 mint：超过一年没用过、服务器端重新生成了 JWT 密钥（`auth.db` 里的 `jwt_secret` 变了）、或换了服务器地址。重跑一次 `mint-seed-token.sh` 并更新 `.env.local` 即可。

配置页只在「没有任何可用凭据且二进制里没有种子」时才会出现，网页版的账号密码就派这个用场。

## 连哪台服务器

App 里已经预填了隧道地址 `https://claude.huaizuo2029.cn`（个人构建默认值，可用 `--dart-define=CLOUDCLI_SERVER_URL=...` 覆盖）。**只需要填一次用户名/密码**，之后 token 和凭据都存进 Keychain，App 自动登录、永不再问。账号就是服务器上网页版的账号（在网页版首次注册）。

| 场景 | 地址填什么 |
| --- | --- |
| 默认（隧道，任何网络都能用） | `https://claude.huaizuo2029.cn`（已预填） |
| 模拟器连本机服务 | `127.0.0.1:3001` |
| 手机连本机服务（同一 Wi-Fi） | 本机局域网 IP，如 `172.18.239.130:3001`（`ipconfig getifaddr en0`） |

隧道是 HTTPS，所以 ATS 其实用不上；`ios/Runner/Info.plist` 仍放开了明文 HTTP（`NSAllowsArbitraryLoads`）并声明了本地网络权限（`NSLocalNetworkUsageDescription`），方便直连内网地址时不被 iOS 拦。

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
