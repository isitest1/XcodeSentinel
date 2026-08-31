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

### 1. テンプレートを選ぶ

File → New → Project → **macOS** タブ → **App**。

| 項目 | 値 |
|---|---|
| Product Name | `XcodeSentinel` |
| Team | Developer ID チーム |
| Organization Identifier | 例 `io.github.isitest1`（bundle id は `io.github.isitest1.XcodeSentinel`） |
| Interface | **SwiftUI** |
| Language | **Swift** |
| Storage | **None**（SwiftData / Core Data は使わない。永続化は `TargetStore` の JSON） |
| Testing System | **None**（単体テストは `Packages/SentinelCore` 側に集約） |
| Host in CloudKit | オフ |

### 2. `App/` 直下へ配置する

Xcode は `XcodeSentinel/XcodeSentinel.xcodeproj` という**ラッパーフォルダ付き**で
生成します。CI（`-project App/XcodeSentinel.xcodeproj`）とリポジトリ規約は
`App/XcodeSentinel.xcodeproj` を前提にしているので:

1. いったん作業用の場所（デスクトップなど）に作成する。
2. `XcodeSentinel.xcodeproj` と、生成された `XcodeSentinel/` フォルダ
   （`Assets.xcassets` と `XcodeSentinel.entitlements` が入っている）を、
   本リポジトリの `App/` 直下へ移動する。
3. テンプレートの `ContentView.swift` と `XcodeSentinel/XcodeSentinelApp.swift` は
   **削除**する（`App/App/XcodeSentinelApp.swift` が置き換え。同名なので削除必須）。
4. Xcode で赤くなったファイル参照を外し、Add Files で既存フォルダを
   ターゲット `XcodeSentinel` に追加する:
   `App/App`, `App/Accessibility`, `App/Automation`, `App/Notifications`,
   `App/Settings`, `App/Targets`, `App/Logging`, `App/Debug`。

### 3. ローカルパッケージをリンク

File → Add Package Dependencies → **Add Local** → `Packages/SentinelCore` を選び、
`SentinelCore` ライブラリをアプリターゲットに追加する。

### 4. ビルド設定

- Deployment Target: **macOS 15**。
- Swift Language Version: **6**、Strict Concurrency Checking: **Complete**。
- App Sandbox: **無効**（Accessibility API で他アプリを操作するため。CLAUDE.md 第 1.6 章）。
- Hardened Runtime: **有効**（Developer ID 配布・notarization のため）。
- `INFOPLIST_KEY_LSUIElement = YES`（Dock アイコンなし、メニューバー常駐。
  Xcode 16 は Info.plist を生成しないためビルド設定で指定する。UI では
  "Application is agent (UIElement)" = YES）。
- Accessibility の使用目的: `NSAccessibilityUsageDescription` を設定（`INFOPLIST_KEY_` でも可）。

### 5. 確認

```sh
xcodebuild -project App/XcodeSentinel.xcodeproj -scheme XcodeSentinel -configuration Debug build
```

が通れば、CI の `app-build` ワークフローも同じビルドで緑になる。

## 実装前に必ず確認すること（CLAUDE.md 第 18 章）

`App/Accessibility` と `App/Automation` の本実装は、AX Inspector で実機のツリーを確認してから
着手してください。推測でコードを書かないでください。確認項目は
[`../docs/accessibility-tree.md`](../docs/accessibility-tree.md) にあります。
