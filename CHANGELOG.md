# 変更履歴

すべての注目すべき変更をこのファイルに記録します。
書式は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に準拠し、
バージョニングは [Semantic Versioning](https://semver.org/lang/ja/) に従います。

## [Unreleased]

### 追加（M2: 検出）

- `TargetIdentity` / `WindowDescriptor` / `TargetResolver`：永続化した対象を
  実行中の Xcode ウィンドウへ再解決（`AXDocument` パス → タイトル内ワークスペース名 →
  表示名 の優先度、同点は `.ambiguous`）。`WorkspacePath` ヘルパ（拡張子除去、`file://`
  正規化）。
- `DetectionEngine` にパネル絞り込み（`PatternSet.panelHints`：`identifiers` /
  `anchorTexts` / `containerRoles`）。当たらなければツリー全体にフォールバック。
- `DetectionEngine.Result` に `panelLocated` と `nearMisses`（`wouldMatchIfEnabled` /
  `blockedByNoneOf` / `blockedByRole`）。設定画面の "Test Detection" 用。
- AX スナップショットのフィクスチャを追加（weekly-limited / awaiting-continue / idle /
  whole-window）。単体テストは合計 ~97 件。
- `App/`：`XcodeWindowEnumerator`、`TargetBinder`、"Test Detection" 結果表示の骨組み。

### 追加（M1: 土台）

- リポジトリの初期構成と Dev Container 設定。
- `SentinelCore` パッケージ（macOS 非依存、Linux でビルド・テスト可能）。
  - `SessionState` 状態機械
  - `AXSnapshot` / `AXNode`（AX ツリーのプレーンなデータモデル、JSON 入出力）
  - `PatternSet` / `DetectionPattern` と `DetectionEngine`（`Patterns.json` による状態判定）
  - `ResetTimeParser`（リセット時刻の抽出と再試行時刻ポリシー）
  - `ResumeScheduler`（優先度付きキュー、同時実行上限、投入間隔、Quiet Hours）
  - `SafetyPolicy`（1 日あたり上限、クールダウン、停止ごとのリトライ上限、Dry-run）
  - `PollingInterval`（状態別ポーリング間隔）
  - `Logging`（構造化ログの継ぎ目。チャット本文は記録しない）
- GitHub Actions: `core-tests`（Linux で `swift test`）、`app-build`（macOS で `xcodebuild`）。
- 日本語の README・Issue / PR テンプレート・`docs/` 雛形。
- `App/` の macOS 専用スキャフォールド（ホストの Xcode でビルド）。
