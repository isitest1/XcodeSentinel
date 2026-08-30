# App/ — macOS アプリ（ホストの Xcode でのみビルド）

この配下は **macOS 専用**です。`AppKit` / `SwiftUI` / `ApplicationServices`（Accessibility API）/
`UserNotifications` / `ServiceManagement` に依存するため、**Dev Container（Linux）ではビルドできません**
（CLAUDE.md 第 15 章）。エディタ上で赤線が出るのは正常です。

## 依存の方向

- `App` は `Packages/SentinelCore` に依存します。**逆方向の依存は禁止**です。
- AX ツリーの読み取りは `App/Accessibility` が行い、結果を `AXSnapshot`（`SentinelCore` の
  プレーンなデータ構造）に変換してから判定ロジックへ渡します。判定は AX API を一切知りません。
- 再開を発火できるのは `ResumeScheduler` を経由する経路のみです（CLAUDE.md 第 4.2 / 7.3 章）。
- すべての AX 操作は単一の直列アクター `AccessibilityActor`（`@AccessibilityActor` グローバルアクター）
  を経由します。AX API はスレッドセーフではありません。

## ディレクトリ

| ディレクトリ | 役割 |
|---|---|
| `App/` | エントリポイント、`MenuBarExtra` |
| `Accessibility/` | `AXUIElement` ラッパー、権限管理、ツリー探索、`AXSnapshot` への変換 |
| `Targets/` | 監視対象（`MonitorTarget`）の登録・永続化・再解決 |
| `Automation/` | 再開操作（入力欄への書き込み、送信ボタンの `AXPress`、送信後の遷移確認） |
| `Notifications/` | ローカル通知（`UserNotifications`）、Webhook 送信 |
| `Settings/` | 設定画面（SwiftUI）、`Patterns.json` 編集 UI、"Test Detection" |
| `Logging/` | `SentinelCore.LogSink` の macOS 実装（`os.Logger` へ転送） |
| `Debug/` | AX Inspector（ツリーのダンプ、JSON エクスポート、パターンのハイライト） |

## Xcode プロジェクトの追加（初回のみ、ホストで作業）

1. ホストの macOS で本リポジトリを開く。
2. Xcode で新規 **macOS App** を作成し、保存先をこの `App/` にする。
   - Product Name: `XcodeSentinel`
   - Interface: SwiftUI / Language: Swift
   - 生成物: `App/XcodeSentinel.xcodeproj`
3. ターゲット設定:
   - `Info.plist` に `LSUIElement = YES`（Dock アイコンなし、メニューバー常駐）。
   - Deployment Target: macOS 15。
   - Swift Language Version: Swift 6、Strict Concurrency Checking: Complete。
   - App Sandbox: **無効**（Accessibility API で他アプリを操作するため。CLAUDE.md 第 1.6 章）。
   - "Hardened Runtime" は有効（Developer ID 配布・notarization のため）。
4. ローカル Swift Package として `Packages/SentinelCore` を追加し、アプリターゲットにリンクする。
5. この `App/` 配下の既存 `.swift` スケルトンをプロジェクトに取り込む。
6. `xcodebuild -project App/XcodeSentinel.xcodeproj -scheme XcodeSentinel -configuration Debug build`
   が通ることを確認する。以降、`app-build` ワークフローが CI で同じビルドを行う。

## 実装前に必ず確認すること（CLAUDE.md 第 18 章）

`App/Accessibility` と `App/Automation` の本実装は、AX Inspector で実機のツリーを確認してから
着手してください。推測でコードを書かないでください。確認項目は
[`../docs/accessibility-tree.md`](../docs/accessibility-tree.md) にあります。
