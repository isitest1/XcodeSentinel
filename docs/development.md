# 開発環境

## 役割分担

| 作業 | 場所 |
|---|---|
| コード編集、Claude Code による実装 | Dev Container |
| `Packages/SentinelCore` のビルド・単体テスト | Dev Container |
| フォーマット・Lint | Dev Container |
| 公開サイト（`docs/site/`）の編集・プレビュー | Dev Container |
| ドキュメント執筆 | Dev Container |
| `App/` のビルド・実行・AX 動作確認 | **ホストの macOS**（Xcode / `xcodebuild`） |
| 署名・notarization・DMG 作成 | **ホストの macOS** |

**Dev Container は Linux コンテナです。** `AppKit` / `SwiftUI` / `ApplicationServices` / `UserNotifications` /
`ServiceManagement` は Linux 版 Swift に存在せず、`xcodebuild` もありません。`App/` を
コンテナ内でビルドしようとしないでください（CLAUDE.md 第 15 章）。

## Dev Container の起動

VS Code で「Reopen in Container」を実行します。`.devcontainer/devcontainer.json` が
`swift:6.0-noble` イメージを使い、`postCreateCommand` で `.devcontainer/post-create.sh` を実行します。

## SentinelCore のビルドとテスト

```sh
swift build --package-path Packages/SentinelCore
swift test  --package-path Packages/SentinelCore
```

### コンテナ内でのテスト実行に関する注意

Apple Silicon 上の Dev Container では、Linux 版 XCTest ランナー（QEMU ユーザーエミュレーション経由）が
1 プロセスで多数のテストを実行するとテスト間の後処理でまれにハングします。個々のスイートは高速かつ安定して
いるため、コンテナ内では次のスクリプトを使ってスイート単位で実行してください。

```sh
Scripts/test-core.sh            # ビルドしてから全スイートを実行
Scripts/test-core.sh --no-build # ビルドを省略
```

CI（ネイティブ x86_64 Linux）では `swift test` が正常に動作し、`core-tests` ワークフローはそれを使います。

## 公開サイトのプレビュー

```sh
http-server docs/site -p 8080
```

ポート 8080 は Dev Container が自動転送します。

## `App/` を編集するときの注意

`App/` 配下は Linux ではコンパイルできず、エディタ上で赤線が出ます（正常です）。

- コンパイル可否をコンテナ内で確認できないため、`App/` の変更は**ホストでのビルド確認とセット**で行ってください。
- 変更は小さく刻み、こまめにホストで `xcodebuild` を通してください。

## ホスト macOS でのビルド

```sh
# リポジトリのルートで（App/ の Xcode プロジェクト追加後）
xcodebuild -scheme XcodeSentinel -configuration Debug build
```
