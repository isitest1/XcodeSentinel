# ホストの Mac / Xcode への引き継ぎ

このリポジトリは Dev Container（Linux）で作れる範囲を作り終えた状態です。
ここから先は **ホストの macOS + Xcode** で続けます。この文書は、
Mac 側の作業内容と、Xcode に組み込まれた Claude への渡し方をまとめたものです。

---

## 1. 現在の状態

### 完成している（Dev Container で実装・テスト済み）

`Packages/SentinelCore/` — macOS 非依存のロジック。**約 126 の単体テストが通っています。**

| モジュール | 内容 | マイルストーン |
|---|---|---|
| `SessionState` | 状態機械 | M1 |
| `AccessibilitySnapshot`（`AXSnapshot` / `AXNode`） | AX ツリーのプレーンなデータ型（JSON 入出力） | M1 |
| `DetectionPatterns` + `DetectionEngine` | `Patterns.json` 駆動の状態判定、パネル絞り込み、near-miss | M1–M2 |
| `ResetTimeParser` | リセット時刻の抽出と再試行時刻ポリシー | M1 |
| `TargetResolver` / `WorkspacePath` | 永続化した対象 → live ウィンドウの再解決 | M2 |
| `ResumeScheduler` | 優先度キュー・同時実行上限・投入間隔・Quiet Hours・`notBefore` 保留 | M1, M3 |
| `SafetyPolicy` | 1 日上限・クールダウン・停止ごとのリトライ上限・Dry-run | M1 |
| `ResumeOrchestrator` | 上記を結線した判定パイプライン（`ingest` / `pump` / `recordSendOutcome`） | M3 |
| `PollingInterval` | 状態別ポーリング間隔 | M1 |
| `WebhookPayloadBuilder` | Webhook ペイロード生成（ntfy / Pushover / Discord / Slack / custom） | M4 |
| `MenuBarStatus` | 全対象の状態集約 → メニューバーアイコン | M4 |
| `Logging` | 構造化ログの継ぎ目（チャット本文を記録しない） | M1 |

公開サイト `docs/site/`（第14章）も EN/JA 揃った状態で完成し、GitHub Pages に
デプロイ済みです（`.github/workflows/pages.yml`）。**スクリーンショットのみ未撮影**
（`docs/site/assets/screenshots/README.md` に撮影リスト）。

### 骨組みのみ（Mac でビルド・実装する）

`App/` 配下すべて。`#if os(macOS)` ガード付きで、`TODO(host):` マーカーがあります。
Dev Container ではコンパイルできないので赤線が出ますが正常です。

| ファイル | 状態 |
|---|---|
| `App/App/XcodeSentinelApp.swift`, `AppModel.swift`, `MenuBarContentView.swift` | エントリと骨組み |
| `App/Accessibility/AccessibilityActor.swift` | 権限チェックのみ実装、グローバルアクター定義済み |
| `App/Accessibility/XcodeWindowEnumerator.swift` | ウィンドウ列挙、おおむね実装済み（実機検証必要） |
| `App/Accessibility/AXTreeReader.swift` | **`node(from:)` が未実装** |
| `App/Targets/MonitorTarget.swift`, `TargetStore.swift`, `TargetBinder.swift` | データ型と永続化は実装済み |
| `App/Automation/ResumeController.swift` | **AX 送信が未実装** |
| `App/Automation/ResumeCoordinator.swift` | オーケストレータの effect ループ実装済み |
| `App/Notifications/Notifier.swift`, `WebhookSender.swift` | 実装済み（`WebhookSender` は `SentinelCore` に委譲） |
| `App/Settings/SettingsView.swift` | タブ構成の骨組み、"Test Detection" 結果表示あり |
| `App/Debug/AXInspectorView.swift` | **ツリー描画・キャプチャが未実装** |
| `App/Logging/OSLogSink.swift` | 実装済み |

---

## 2. 第18章のゲート（最重要）

CLAUDE.md 第18章のとおり、**AX 構造を実機で確認するまで Detection と Automation の
本実装に入らないでください。** 推測でコードを書かない。

確認する項目は `docs/accessibility-tree.md` のチェックリストにあります（要約）:

- Claude パネルは独立 AX ウィンドウか、Xcode ウィンドウの子か
- 入力欄の role と `AXValue` の書き込み可否
- 制限メッセージの要素と文言（session / weekly の区別）
- 送信ボタンの `AXPress` が効くか
- `AXDocument` が返す値（`file://` URL / パス / 未露出）
- Claude パネルを一意に指す `AXIdentifier` の有無
- 最小化・非アクティブでも AX ツリーを読めるか
- Xcode の Claude 連携に `/config` 相当の自動継続設定が後から入っていないか
  （入っていたら本プロジェクトの前提が崩れる。**最初に確認**）

---

## 3. Mac 側の作業順序

```sh
git clone https://github.com/isitest1/XcodeSentinel.git
cd XcodeSentinel
swift test --package-path Packages/SentinelCore   # Mac ではそのまま通る（下記 6 参照）
```

1. **Xcode プロジェクト作成** — `App/README.md` の「Xcode プロジェクトの追加」手順。
   `App/XcodeSentinel.xcodeproj` を作り、`Packages/SentinelCore` をローカルパッケージとして
   リンク。`App/` 配下の既存 `.swift` を取り込む。
   - `LSUIElement = YES`、Deployment Target macOS 15、Swift 6 / Strict Concurrency = Complete、
     App Sandbox = 無効、Hardened Runtime = 有効。
2. **ビルドを通す** — `xcodebuild -project App/XcodeSentinel.xcodeproj -scheme XcodeSentinel
   -configuration Debug build`。通れば CI の `app-build` ジョブも緑になる。
3. **権限フローとウィンドウ列挙** — `AccessibilityActor` / `AccessibilityPermission` /
   `XcodeWindowEnumerator` を実機で確認。`AXDocument` の実値を見て `TargetResolver` の
   高信頼一致が効くか確認。
4. **AX Inspector（M1 の最重要ツール）** — `AXInspectorView` と `AXTreeReader.node(from:)` を
   実装。対象ウィンドウをキャプチャして `AXSnapshot` を JSON エクスポートできるようにする。
5. **フィクスチャ差し替え** — 実機ダンプで
   `Packages/SentinelCore/Tests/SentinelCoreTests/Fixtures/*.json` を置き換え、
   `Patterns.json`（`panelHints.identifiers` を含む）を実文言に合わせて調整。
   `swift test` で回帰を確認。
6. **Detection の結線** — ポーリングループ（`PollingInterval`）→ `AXTreeReader` →
   `DetectionEngine.classify` → `ResumeCoordinator.handle(observation:)`。
7. **Automation** — `ResumeController.resume(window:prompt:dryRun:)` を実装
   （入力欄へ `AXValue` 設定 → 送信ボタン `AXPress` → 15 秒以内に `.working` 遷移確認）。
   まず Dry-run で。CGEvent キーストロークは最終手段、フォーカス確認必須。
8. **通知と設定 UI** — `Notifier` の実挙動確認、Settings の各ペイン、"Add Target" と
   "Test Detection" の実装、Quiet Hours の設定 UI。
9. **M5 配布** — Developer ID 署名、notarization、DMG 作成。`.github/workflows/release.yml`
   は骨組みがあるので TODO とシークレット（`DEVELOPER_ID_APP_CERT_*` ほか）を埋める。
   スクリーンショット撮影 → `docs/site/assets/screenshots/`。
10. **相互リンク（第14.6章）** — `isitest1/portfolio-hub` の `src/data/projects.ts` に
    XcodeSentinel のカードを追加し、リンク先を本サイトのトップにする。片方向で終わらせない。

---

## 4. Xcode の Claude への渡し方

Xcode の Claude 連携はワークスペースのファイルを読めます。リポジトリを Xcode で開いた状態で、
最初のメッセージに次を伝えてください（趣旨。文言は任意）:

> `CLAUDE.md` と `docs/xcode-handoff.md` を読んで。`Packages/SentinelCore`（M1〜M4）は
> 実装・テスト済み。`App/` は `#if os(macOS)` ガード付きの骨組みで、`TODO(host)` が
> 未実装箇所。`docs/xcode-handoff.md` 第3章の順に進めて。まず第2章（CLAUDE.md 第18章の
> ゲート）の AX 確認と AX Inspector を先にやること。確認が済むまで Detection と
> Automation の本実装はしない。`SentinelCore` に `AppKit` / `SwiftUI` /
> `ApplicationServices` を import しない。

補足として毎回効かせたい注意（CLAUDE.md 第17章）:

- 画面座標の決め打ちクリックをしない
- `unknown` のとき自動送信しない
- 承認・質問に自動応答しない（既定で無効、明示的有効化なしに動かさない）
- 制限到達時に短間隔リトライ連打しない
- チャット本文・ソースコードを Webhook やログに出さない
- 製品名に "Claude" / "Anthropic" を入れない
- 「5 時間制限を突破できる」と書かない
- 公開サイトは EN / JA を同時に更新する

---

## 5. リポジトリの決まりごと（要点）

- ドキュメント・README・Issue/PR テンプレート・CHANGELOG は**日本語**。
  UI 文言・コード識別子・コメント・コミットメッセージは**英語**（Conventional Commits）。
- `App` は `SentinelCore` に依存。**逆依存禁止。**
- 新しいロジックは「まず `SentinelCore` に置けないか」を先に検討する。
- コミットは `main` に直接ではなくブランチ + PR（`.github/pull_request_template.md` あり）。

---

## 6. テストについて

- **Mac では `swift test --package-path Packages/SentinelCore` がそのまま使えます。**
- Dev Container 上でだけ、QEMU 上の Linux XCTest ランナーがテスト後処理でハングすることが
  あります。そのための回避スクリプトが `Scripts/test-core.sh`（スイート単位実行）です。
  Mac では不要。
- CI は 4 本:
  - `core-tests`（Linux, `swift test`）— `Packages/SentinelCore/**` 変更で起動
  - `app-build`（macOS, `xcodebuild`）— `App/**` または `Packages/SentinelCore/**` 変更で起動。
    現在は「`App/XcodeSentinel.xcodeproj` 未追加」で意図的に失敗する。手順 1–2 で緑になる。
  - `pages`（`docs/site/**` 変更でサイトを再デプロイ、EN/JA パリティを検査）
  - `release`（`v*` タグ push で起動）— 署名・notarization・DMG の**骨組み**。
    手順 9 で TODO を埋める。
