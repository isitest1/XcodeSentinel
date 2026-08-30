# XcodeSentinel（作業仮称）

macOS のメニューバーに常駐し、**Xcode に組み込まれた Claude のコーディングセッションを監視して、停止したときに自動的に再開させる**ユーティリティです。

開発者が席を外している間に、Claude が利用量制限や確認待ちで止まったまま放置される時間をなくすことを目的にしています。

> **これは Anthropic および Apple の公式製品ではありません。**

---

## 1. 何を解決するか

Xcode で Claude にコードを書かせていると、次のような理由で作業が止まります。

- 5 時間のセッション利用量制限に達した
- 週次の利用量上限に達した
- 出力が長くて「続ける」待ちになっている

外出中・就寝中はこの停止に気づけず、制限が解除されてからも何時間も止まったままになります。XcodeSentinel は、**制限が解除されたあとにあなた自身のセッションを再開する**のを肩代わりし、止まったことを外出先へ通知します。

## 2. なぜ Xcode 限定なのか

**対象は Xcode の Claude 連携のみです。VS Code 拡張やターミナルの Claude Code は対象外です。**

Claude Code には既に公式の自動継続機能があります（`/config` の "Continue automatically at usage limit"、既定で有効）。VS Code 拡張も Claude Code を基盤とするためこの恩恵を受けます。

一方、**Xcode の Claude 連携は Apple の IDE 機能で、Claude Code とは別系統**です。上記の自動継続は適用されません。ここに機能上の空白があり、それがこのアプリの存在理由です。

なお Claude Code の自動継続も万能ではなく、以下は自動では解決されません（将来的な検討事項）。

- 週次制限（自動継続はセッション制限のみ対象）
- 権限確認・ツール実行の承認待ち
- Claude が質問を投げて応答待ちになった場合
- 異常終了
- 外出先への通知

## 3. できないこと（免責）

**本アプリは利用量制限を回避・突破するものではありません。** 制限が解除されたあとに、ユーザー自身の既存セッションを再開する補助ツールです。制限中に何かを送り続けることはしません。

- 権限確認・Claude からの質問には**自動応答しません**（通知のみ）。
- 状態が判別できないときは**何も送信しません**（通知のみ）。
- チャット本文やソースコードを外部へ送信することはありません（通知は対象名・状態・時刻のみ）。

## 4. 必要な権限

| 権限 | 用途 |
|---|---|
| アクセシビリティ | Xcode ウィンドウ内の Claude パネルの状態を読み取り、入力欄への文字入力と送信ボタンの押下を行うため |

- 画面収録権限は**使用しません**（OCR やスクリーンショット解析には頼りません）。
- 読み取る内容・送信する内容・送信しない内容の詳細は [`docs/`](docs/) と公開サイトの privacy ページに記載します。

## 5. インストール

Developer ID 署名 + notarization 済みの DMG を [GitHub Releases](../../releases/latest) で配布します（App Store では配布しません。理由は次項）。

初回起動時の Gatekeeper の扱いと詳細な手順は公開サイトの getting-started を参照してください。

## 6. なぜ Mac App Store で配布しないのか

本アプリは他アプリ（Xcode）をアクセシビリティ API で操作します。App Sandbox の制約により、この種のアプリは Mac App Store では配布できません。配布と告知は GitHub Releases と公開サイトで完結させます。

## 7. Xcode 更新で検出が壊れたら

Xcode 内 Claude パネルのアクセシビリティ構造は非公開仕様で、Xcode の更新で変わり得ます。検出が壊れた場合:

1. アプリ内の **AX Inspector** で対象ウィンドウのツリーを JSON エクスポートする
2. その JSON を添えて Issue を作成する（実在のプロジェクト名やパスが含まれないことを確認してください）
3. 検出パターンは `Patterns.json`（設定画面から編集可）に外出しされているため、多くの場合は再ビルドなしで対応できます

## 8. 開発環境

| 作業 | 場所 |
|---|---|
| コード編集、`SentinelCore` のビルド・テスト、公開サイトのプレビュー、ドキュメント執筆 | VS Code Dev Container（Linux） |
| `App/`（SwiftUI / AppKit / アクセシビリティ）のビルド・実行・実機確認、署名・notarization・DMG 作成 | ホストの macOS（Xcode / `xcodebuild`） |

**Dev Container は Linux コンテナのため、macOS アプリはビルドできません。** これは原理的な制約です。詳細は [`docs/development.md`](docs/development.md)。

```sh
# Dev Container 内
swift build --package-path Packages/SentinelCore
swift test  --package-path Packages/SentinelCore
http-server docs/site -p 8080     # 公開サイトのプレビュー
```

## 9. リポジトリ構成

```
Packages/SentinelCore/   macOS 非依存のロジック（Linux でビルド・テスト可）
App/                     macOS 専用アプリ（ホストの Xcode でのみビルド）
docs/                    設計・運用ドキュメント（日本語）
docs/site/               公開サイト（GitHub Pages、英語 / 日本語）
```

## 10. 公開サイト

App Store で配布しない以上、公開サイトが唯一の入口です。配布・使い方・プライバシー説明はすべてサイトが担います。

- サイト: （公開後にリンクを記載）
- 作者の他のプロジェクト: https://isitest1.github.io/portfolio-hub/ja

## 11. ライセンス

MIT License（[`LICENSE`](LICENSE)）。
