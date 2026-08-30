# CLAUDE.md

このファイルは、本リポジトリで作業する Claude Code（および VS Code 上の Claude 拡張）に対する開発指示書です。

**言語ルール：このファイルおよびリポジトリのドキュメント類は日本語で記述します。ただし、アプリの UI 文言・コード内の識別子・コード内コメント・コミットメッセージは英語で記述します。公開 Web サイトのみ、英語と日本語の両方を用意します（詳細は第 14 章）。**

---

## 1. プロジェクト概要

### 1.1 何を作るのか

macOS のメニューバーに常駐し、**Xcode に組み込まれた Claude のコーディングセッションを監視して、停止した場合に自動的に再開させる**ユーティリティアプリです。

開発者が席を外している間（外出中・就寝中・別作業中）に、Claude が利用量制限や確認待ちで停止したまま何時間も放置される問題を解決します。

### 1.2 スコープは Xcode 限定とする（重要な設計判断）

**本アプリの対象は Xcode の Claude 連携のみです。VS Code / ターミナルの Claude Code は対象外とします。**

理由は、Claude Code 側には既に公式の自動継続機能が存在するためです。

- Claude Code v2.1.234（2026 年 8 月 17 日リリース）で、利用量制限がリセットされた際にセッションを自動的に継続する挙動が入りました。**これは既定で有効**で、無効化したい場合に `/config` の "Continue automatically at usage limit" を切る、という形になっています。
- Claude Code Desktop の Code タブでも、セッション制限のカードに "Auto-continue when limits reset" のチェックボックスが表示され、リセット時刻とともに自動再開が予告されます。
- VS Code 拡張は Claude Code を基盤としているため、この恩恵を受けます。

一方、**Xcode の Claude 連携は Apple の IDE 機能であり、Claude Code とは別系統です。上記の `/config` 設定も自動継続の挙動も適用されません。** ここに明確な機能上の空白があり、それが本アプリの存在理由です。

### 1.3 ただし「Claude Code なら完全に解決済み」ではない

将来的な機能拡張の判断材料として、以下は記録しておきます。README やサイトでの説明にも使用してください。

Claude Code の自動継続は、**セッション制限（5 時間ウィンドウ）にのみ適用されます。週次制限のカードには自動継続の選択肢が提示されません。** また、以下は Claude Code でも自動では解決されません。

- 権限確認・ツール実行の承認待ちで止まった場合
- Claude が質問を投げて応答待ちになった場合
- エラーで異常終了した場合
- 外出先の端末へ状況を通知すること

したがって本アプリの機能のうち、「状態の判別」「外出先への通知」「複数セッションの再開スケジューリング」の部分は、将来 Claude Code 系へ展開する余地があります。ただし**初版のスコープには含めません。**

### 1.4 率直なリスク認識（開発を進める前提として共有する）

- 対象を Xcode に絞った結果、**想定ユーザーは「Xcode で Claude を使って iOS/macOS アプリを開発している人」に限定されます。** 市場は小さいです。まず自分の実運用のためのツールとして作り、公開はその副産物、という位置づけが現実的です。
- **Apple が将来の Xcode アップデートで同等の機能を入れれば、本アプリの存在意義は消えます。** その前提で、作り込みすぎないこと。MVP を素早く完成させることを最優先します。
- Xcode の Accessibility ツリー構造は非公開仕様であり、Xcode の更新で壊れ得ます。これは織り込み済みの前提です（第 10 章の AX Inspector が対策）。

### 1.5 プロジェクト名

作業上の仮称は `XcodeSentinel` とします。

> **注意:** 製品名・リポジトリ名・ドメインに "Claude" や "Anthropic" を含めないでください。第三者の商標であり、公式ツールと誤認される恐れがあります。説明文中で「Xcode の Claude 連携と併用する」旨を記述するのは問題ありませんが、名称には含めない方針とします。

### 1.6 開発・配布環境

| 項目 | 内容 |
|---|---|
| 開発エディタ | VS Code + Dev Container（第 15 章） |
| ビルド・署名・実機確認 | ホストの macOS 上の Xcode / `xcodebuild`（コンテナ内では不可） |
| 言語 | Swift 6 / SwiftUI |
| 最低対応 OS | macOS 15 以降を想定（`MenuBarExtra`、`SMAppService` を利用するため） |
| リポジトリ | GitHub パブリックリポジトリ |
| 配布 | Developer ID 署名 + notarization 済みの DMG を GitHub Releases で配布 |
| 公開サイト | GitHub Pages（`docs/site/`） |

> **重要（設計上の前提）:** 本アプリは他アプリ（Xcode）を Accessibility API で操作するため、**App Sandbox の制約により Mac App Store では配布できません。** App Store 提出を前提とした設計・実装は行わないでください。配布と告知は、GitHub Releases と自前の GitHub Pages サイトで完結させます。

---

## 2. ドキュメントと UI の言語ルール

このルールは例外なく守ってください。

| 対象 | 言語 |
|---|---|
| `README.md` | **日本語** |
| `CLAUDE.md`（本ファイル） | **日本語** |
| `docs/` 配下の設計・運用ドキュメント | **日本語** |
| GitHub の About / トピック説明 | **日本語** |
| Issue / PR テンプレート | **日本語** |
| CHANGELOG | **日本語** |
| **公開 Web サイト** | **英語・日本語の両方（切替式。第 14 章参照）** |
| アプリの UI 文言（ボタン・ラベル・メニュー・設定画面） | **英語** |
| 通知の本文 | **英語** |
| ログ出力 | **英語** |
| ソースコードの識別子・コメント | **英語** |
| コミットメッセージ | **英語**（Conventional Commits 形式） |

アプリの UI 文言は将来のローカライズに備え、直書きせず `Localizable.strings`（`en` のみ）経由で取得してください。

---

## 3. 前提知識：Claude の利用量制限の実際の仕様

自動再開ロジックの設計は、この仕様の正確な理解に依存します。誤った前提でロジックを組まないでください。

- 利用量制限は **5 時間のローリングセッション**です。固定時刻ではなく、**そのセッションで最初のメッセージを送った時点から 5 時間**でリセットされます。
- 5 時間セッションとは**別に、週次の上限**が存在します。週次上限に達した場合、**5 時間待ってもリセットされません。**
- 利用量は **claude.ai / Claude Code / Claude Desktop / Xcode の Claude 連携などの間で共有される単一のプール**です。Xcode のウィンドウを 4 つ並行で走らせれば、消費速度も概ね 4 倍になります。
- 制限に達した際、追加の使用クレジット（API レート課金）で継続する設定を有効にしているユーザーも存在します。その場合は制限で停止しません。

### 設計上の帰結（必ず反映すること）

1. **「5 時間タイマー」で決め打ちしない。** 必ず UI 上の状態と、表示されているリセット時刻の文字列を読み取って判断します。時刻が読み取れた場合はそれを優先し、読み取れない場合のみ推定値でフォールバックします。
2. **週次上限とセッション上限を明確に区別する。** 週次上限を検出した場合、5 分おきのポーリングで再試行するのは無意味です。長い待機に切り替え、ユーザーへ通知します。
3. **複数対象を同時に再開させない。** 制限解除直後に登録済みの 5 セッションが一斉に走り出すと、数十分で再び制限に到達します。再開は**逐次実行のキュー**とし、優先度順に 1 つずつ、間隔を空けて投入します（第 7.3 章の Resume Scheduler）。
4. **本アプリは制限を回避するものではありません。** 制限が解除された後に、ユーザー自身の既存セッションを再開する補助に徹します。README と公開サイトにこの旨を明記してください。

---

## 4. アーキテクチャ

### 4.1 リポジトリ構成

Dev Container（Linux）でテストできる範囲を最大化するため、**純粋ロジックを macOS 依存のない Swift Package に切り出します。** これは第 15 章の開発環境と直結する、最重要の構造上の決定です。

```
XcodeSentinel/
├── .devcontainer/
│   └── devcontainer.json         # 第 15 章
├── .vscode/
│   └── tasks.json
├── Packages/
│   └── SentinelCore/             # ★ macOS 非依存。Linux でビルド・テスト可能
│       ├── Sources/SentinelCore/
│       │   ├── SessionState.swift        # State machine
│       │   ├── ResetTimeParser.swift     # Limit-message time parsing
│       │   ├── DetectionPatterns.swift   # Patterns.json model + matcher
│       │   ├── ResumeScheduler.swift     # Queue, priority, quiet hours
│       │   ├── SafetyPolicy.swift        # Retry caps, cooldowns
│       │   └── AccessibilitySnapshot.swift # Plain data model of an AX tree
│       └── Tests/SentinelCoreTests/
├── App/                          # ★ macOS 専用。ホストの Xcode でのみビルド
│   ├── App/                      # エントリポイント、MenuBarExtra
│   ├── Accessibility/            # AXUIElement のラッパー、権限管理、ツリー探索
│   ├── Targets/                  # 監視対象の登録・永続化
│   ├── Automation/               # 再開操作（テキスト投入・送信・ボタン押下）
│   ├── Notifications/            # ローカル通知、Webhook 送信
│   ├── Settings/                 # 設定画面（SwiftUI）
│   ├── Logging/
│   └── Debug/                    # AX Inspector（第 10 章）
├── docs/
│   └── site/                     # GitHub Pages（第 14 章）
└── CLAUDE.md
```

### 4.2 依存の方向

- `App` は `SentinelCore` に依存します。**逆方向の依存は禁止です。**
- `SentinelCore` は `Foundation` のみに依存し、**`AppKit` / `ApplicationServices` / `SwiftUI` を import してはいけません。** Linux でビルドが通らなくなった時点で、切り分けに失敗しています。
- AX ツリーの読み取りは `App` 側が行い、結果を `AccessibilitySnapshot`（ただのデータ構造）に変換してから `SentinelCore` に渡します。判定ロジックは AX API を一切知りません。
- 状態判定と再開実行は分離します。`ResumeScheduler` が唯一、再開を発火できる層です。これにより「同時に複数を再開してしまう」事故を構造的に防ぎます。
- すべての AX 操作は単一の直列アクター（`AccessibilityActor`）を経由させます。AX API はスレッドセーフではありません。

---

## 5. 監視対象（Target）の設計

### 5.1 対象の識別

Xcode のウィンドウを識別するキーは、**ウィンドウタイトルではなく、可能な限り安定した属性の組み合わせ**とします。

優先順位:

1. Xcode のプロセス PID + ウィンドウの `AXDocument`（ワークスペースのファイル URL）
2. `AXTitle` に含まれるワークスペース名（`.xcodeproj` / `.xcworkspace` 名）
3. ユーザーが手動で付けた表示名（`displayName`）

Xcode を再起動すると PID は変わるため、**永続化するのはワークスペースのパスと表示名**とし、起動時にそれらから現在のウィンドウを再解決します。

### 5.2 Target のデータモデル

```swift
struct MonitorTarget: Codable, Identifiable, Sendable {
    let id: UUID
    var displayName: String            // User-facing label, e.g. "SampleApp - main"
    var workspacePath: String          // Resolved on relaunch
    var isEnabled: Bool
    var priority: Int                  // Lower runs first in the resume queue
    var resumePrompt: String           // Default: "Please continue from where you stopped."
    var maxAutoResumesPerDay: Int      // Safety cap, default 12
    var minIntervalBetweenResumes: TimeInterval  // Default 120s
    var notifyOnStall: Bool
    var requiresManualApprovalForDestructiveStops: Bool
}
```

### 5.3 登録フロー（UI は英語）

1. 設定画面で "Add Target" を押す
2. 現在起動中の Xcode ウィンドウの一覧を表示する（ワークスペース名・ウィンドウタイトル）
3. ユーザーが選択し、表示名と再開文言を入力する
4. "Test Detection" ボタンで、そのウィンドウから Claude パネルを見つけられるか即座に検証し、結果を表示する

**この "Test Detection" は必須機能です。** 動くかどうかが実行時までわからない設計にはしないでください。

---

## 6. 状態検出（Detection）

### 6.1 状態機械

```swift
public enum SessionState: Equatable, Sendable {
    case idle                             // No active task
    case working                          // Claude is generating / running tools
    case awaitingContinue                 // A "Continue" affordance is present
    case sessionLimited(resetAt: Date?)   // 5-hour session limit
    case weeklyLimited(resetAt: Date?)    // Weekly limit
    case awaitingApproval                 // Permission / tool approval prompt
    case awaitingUserAnswer               // Claude asked a question
    case errored(message: String)
    case completed
    case unknown                          // Detection failed
}
```

### 6.2 判定の原則

- **画面座標のハードコードは禁止です。** すべて AX ツリーの探索で要素を特定します。
- 判定は UI テキストの部分一致に頼らざるを得ませんが、**マッチ用の文字列はコードに直書きせず、`Resources/Patterns.json` に外出し**してください。Xcode 側の文言変更に、アプリの再ビルドなしで追従できるようにします。ユーザーが設定画面からパターンを編集・追加できるようにします。
- `unknown` を `working` と誤認しないでください。判定できない場合は `unknown` として扱い、自動操作は行わず通知に留めます。**判定できないときに勝手に何かを送信するのが最悪の挙動です。**

### 6.3 リセット時刻の抽出

制限メッセージに含まれる時刻表現（例: `Resets at 2:15 PM`、`resets 14:15`、相対表現）をパースします。

- パース成功 → その時刻の 60 秒後を再試行時刻とする
- パース失敗 → セッション制限なら「検出時刻 + 5 時間 + 5 分」、週次制限なら「6 時間後に再確認」とする
- パース結果は必ずログと UI に表示し、ユーザーが誤りに気づけるようにする

### 6.4 ポーリング間隔

固定間隔ではなく、状態に応じて可変にします。

| 状態 | 間隔 |
|---|---|
| `working` | 30 秒 |
| `awaitingContinue` | 10 秒 |
| `sessionLimited` | リセット予定時刻の 10 分前までは 5 分、以降は 30 秒 |
| `weeklyLimited` | 30 分 |
| `unknown` | 60 秒（3 回連続で unknown なら通知して監視を一時停止） |

---

## 7. 自動再開（Automation）

### 7.1 操作方法

1. AX ツリーから対象ウィンドウ内のチャット入力欄（`AXTextArea` / `AXTextField`）を特定する
2. `AXValue` に再開文言を設定する
3. 送信ボタン（`AXButton`）が特定できればそれを `AXPress` する。できない場合のみ Return キー送出にフォールバックする
4. 送信後、状態が `working` に遷移したかを 15 秒以内に確認する。遷移しなければ失敗として扱い、再送はせずに通知する

**キーストローク合成（CGEvent）は最終手段です。** フォーカスが別ウィンドウにあるときに文字列が意図しない場所へ入力される事故を防ぐため、使用する場合は必ず対象ウィンドウのフォーカスを確認してから行い、失敗時は即座に中断してください。

### 7.2 絶対に守る安全策

- **1 回の停止に対する自動再開は 1 回まで。** 再開後に再び停止した場合、同じ理由なら 2 回目を試みてよいが、3 回目以降は停止して通知します。
- **1 日あたりの自動再開回数に上限を設ける**（既定 12 回／対象）。
- **`awaitingApproval` では自動応答しない。** 権限確認やツール実行の承認は、ユーザーの判断が必要です。通知のみ行います。設定で許可した場合でも、既定は「通知のみ」とします。
- **`awaitingUserAnswer`（Claude が質問して止まった）でも自動応答しない。** 「continue」と送るのは有害な場合があります。通知に留めます。
- **Dry-run モードを実装する。** 検出だけ行い、実際の送信は行わずログに「何を送るはずだったか」を記録します。初期セットアップ時はこのモードを推奨します。

### 7.3 Resume Scheduler

利用量プールが共有されている以上、これは飾りではなく中核機能です。

- 再開可能になった対象は、即時実行せず**キューに積む**
- キューは `priority` 昇順、同値なら停止した時刻が古い順
- **同時に走らせる対象数の上限**（既定 1、設定で最大 3）
- キュー内の投入間隔（既定 90 秒）
- "Quiet Hours"（例: 01:00–07:00 は通知のみで再開しない）を設定可能にする

このロジックは `SentinelCore` に置き、Dev Container 上の単体テストで検証します。

---

## 8. 通知

### 8.1 ローカル通知（`UserNotifications`）

英語で、状態・対象名・次アクションを 1 行で伝えます。

```
[SampleApp] Session limit reached. Auto-resume at 14:32.
[SampleApp] Resumed automatically. Working.
[DemoKit] Stopped: waiting for your approval. No action taken.
[DemoKit] Weekly limit reached. Auto-resume is paused.
```

### 8.2 外出先への通知（重要度：高）

このアプリの価値の大半は「外出中でも状況がわかること」にあります。ローカル通知だけでは Mac の前にいないと意味がありません。

- 汎用 Webhook 送信機能を実装します（URL とテンプレートをユーザーが設定）
- ntfy / Pushover / Discord / Slack の各形式に対応するプリセットを同梱します
- 送信内容に**ソースコードやチャット本文を含めない**こと。対象の表示名と状態・時刻のみとします（プライバシーおよび情報漏洩防止のため）

---

## 9. 権限と起動

- Accessibility 権限が必須です。`AXIsProcessTrustedWithOptions` で確認し、未許可なら設定画面への導線を出します。
- 権限が途中で失われるケース（アプリ再署名・OS アップデート）を検出し、通知します。
- ログイン時起動は `SMAppService.mainApp.register()` を使用します。`launchd` の plist を手書きしないでください。
- Screen Recording 権限は**必要としない設計**にします。OCR やスクリーンショット解析には頼りません（脆弱かつ権限要求が重いため）。

---

## 10. Debug / AX Inspector（開発上の最重要ツール）

Xcode 内の Claude パネルの Accessibility ツリー構造は公開仕様ではなく、Xcode のバージョンアップで変わり得ます。したがって、**アプリ自身に AX ツリーのダンプ機能を組み込みます。**

- 選択したウィンドウの AX ツリーを、role / title / value / identifier 付きで階層表示する
- 現在マッチしているパターンをハイライトする
- ツリーを **JSON としてエクスポートできる**（Issue 報告時にユーザーが添付できる／Dev Container 上のテストフィクスチャとして使える）
- テキスト要素を検索できる

エクスポートした JSON は `Packages/SentinelCore/Tests/Fixtures/` に置き、**Linux 上の単体テストで判定ロジックを回帰検証します。** これが第 4.1 章のパッケージ分割を採る最大の実利です。

これがないと、Xcode が更新されるたびに開発が止まります。**MVP に含めてください。**

---

## 11. 開発の進め方（マイルストーン）

### M1: 土台
- Dev Container の構築、`SentinelCore` パッケージの雛形と CI
- メニューバー常駐、Accessibility 権限取得、Xcode ウィンドウ一覧の取得
- AX Inspector と JSON エクスポート

### M2: 検出
- 対象の登録・永続化・再解決
- 状態機械と `Patterns.json` による判定（`SentinelCore`）
- 実機の AX ダンプをフィクスチャ化した単体テスト
- "Test Detection"

### M3: 再開
- Dry-run モードでの再開シミュレーション
- 実際の送信、成否確認
- 安全上限とクールダウン

### M4: スケジューラと通知
- Resume Scheduler、Quiet Hours
- ローカル通知、Webhook

### M5: 配布と公開
- Developer ID 署名 + notarization
- DMG 作成の自動化、GitHub Actions によるリリース
- 日本語 README、日本語 Issue テンプレート
- **公開 Web サイト（第 14 章）の構築と公開**

---

## 12. コーディング規約

- Swift 6 の strict concurrency を有効にします。AX 操作は独自のグローバルアクター（`@AccessibilityActor`）に隔離します。
- **単体テストは `SentinelCore` に集約します。** 特に以下は必須です。
  - リセット時刻パーサのテスト（各種フォーマット・タイムゾーン・日跨ぎ・夏時間）
  - Resume Scheduler のテスト（同時実行上限、優先度、Quiet Hours）
  - 状態遷移のテスト（unknown 連続時の停止など）
  - AX スナップショット JSON からの状態判定テスト
- 時刻を扱うコードは `Date()` を直接呼ばず、`Clock` を注入可能にします。テスト不能になります。
- `print` を使わず、`Logging` モジュール経由で構造化ログを出します。ログには**チャット本文を記録しない**（既定）。デバッグ用の詳細ログは明示的なオプトインとします。
- 依存ライブラリは原則追加しません。標準フレームワークのみで完結させます。

---

## 13. リポジトリのドキュメント（すべて日本語）

`README.md` に必ず含めるもの:

1. このアプリが何を解決するか
2. **スコープが Xcode 限定である理由**（Claude Code / VS Code 側には公式の自動継続があること。第 1.2 章の内容）
3. **免責:「本アプリは利用量制限を回避・突破するものではありません。制限が解除された後に、ユーザー自身のセッションを再開する補助ツールです」** という明記
4. Accessibility 権限が必要な理由と、何をしているか（透明性）
5. Mac App Store では配布できない理由
6. Xcode のバージョン変更で検出が壊れ得ること、その際の AX Inspector を使った報告方法
7. インストール手順（notarization 済み DMG、Gatekeeper の扱い）
8. 開発環境のセットアップ（Dev Container と、ホスト macOS でのビルドの役割分担）
9. **公開サイトへのリンク**
10. ライセンス（MIT を想定）

`docs/` に置くもの:

- `docs/accessibility-tree.md` — 判明している Xcode の AX 構造のメモ
- `docs/detection-patterns.md` — `Patterns.json` の書き方
- `docs/troubleshooting.md` — 検出できないときの手順
- `docs/development.md` — Dev Container の使い方、ホストでのビルド手順

---

## 14. 公開 Web サイト（GitHub Pages）

App Store で配布できない以上、**公式サイトが唯一の入口になります。** 配布・信頼・使い方の説明を、すべてこのサイトが担います。片手間で作らず、成果物として作り込んでください。

### 14.1 技術方針

- 同一リポジトリの `docs/site/` を GitHub Pages の公開ディレクトリとします
- **静的サイトジェネレータもビルドステップも使いません。** 素の HTML + CSS + 最小限の JavaScript のみとします。ビルドが必要になると、README とサイトの内容がすぐ乖離します
- 外部 CDN、フォント配信、アナリティクス、トラッキングは一切入れません。フォントはシステムフォントスタックを使用します
- ダークモード対応（`prefers-color-scheme`）
- レスポンシブ対応（スマートフォンで読めること。外出先から見る用途があるため）
- Dev Container 内でプレビューできること（第 15 章のポート転送を使用）

### 14.2 多言語対応（英語 / 日本語 切替式）

- URL 構成は `/en/` と `/ja/` のディレクトリ分けとします。ルート `/` は `navigator.language` を JavaScript で見て振り分け、判定できない場合は `/en/` へ送ります
- **ヘッダー右上に言語切替リンク（EN / 日本語）を常時配置します。** 切替時は、同じページの対応する言語版へ遷移すること（トップに戻さない）
- 選択した言語は `localStorage` に保存し、次回訪問時に優先します
- `<html lang>` を正しく設定し、各ページに `<link rel="alternate" hreflang="...">` を相互に張ります
- **翻訳は「同じ内容の別言語版」とし、片方だけに情報がある状態を作らないこと。** 更新時は両方を必ず同時に更新します
- 文言は `docs/site/i18n/en.json` と `ja.json` に集約し、HTML への直書きを避けます

### 14.3 必須のページ構成

各言語で以下を用意します。

| ページ | 内容 |
|---|---|
| `index.html` | ヒーロー（一行の価値提案）、スクリーンショット、解決する課題、主な機能、ダウンロードボタン、動作要件 |
| `getting-started.html` | インストールから初回設定完了までの手順。**スクリーンショット必須** |
| `guide.html` | 全機能の詳細な使い方。監視対象の追加、再開文言、スケジューラ、Quiet Hours、Webhook 通知の設定 |
| `troubleshooting.html` | 検出できない場合、権限が外れた場合、Xcode 更新後の対処、AX Inspector の使い方 |
| `privacy.html` | 何を読み取り、何を送信し、何を送信しないかの明示 |
| `faq.html` | 後述の必須項目を含む |
| `changelog.html` | リリース履歴（`CHANGELOG.md` と内容を一致させる） |

### 14.4 スクリーンショットの要件

- 配置場所は `docs/site/assets/screenshots/`
- **Retina 解像度（2x）で撮影し、幅 1600px 程度に統一**。`srcset` で 1x / 2x を出し分ける
- ライトモードとダークモードの両方を用意し、`<picture>` で `prefers-color-scheme` に応じて切り替える
- **最低限、以下を撮影すること**
  1. メニューバーのアイコンとドロップダウン（監視中の対象一覧と状態表示）
  2. 監視対象の追加画面（Xcode ウィンドウ一覧が出ているところ）
  3. "Test Detection" の成功結果
  4. AX Inspector の画面
  5. 設定画面（スケジューラ / Quiet Hours）
  6. Webhook 通知の設定画面
  7. 実際に届いた macOS 通知
  8. 実際に届いたスマートフォンの通知
- **スクリーンショットに実在のプロジェクト名・ファイルパス・個人情報が写り込まないこと。** ダミーのワークスペース名（`SampleApp`, `DemoKit` など）で撮影する
- すべての画像に意味のある `alt` テキストを英語・日本語それぞれで付ける
- `loading="lazy"` を付け、PNG は最適化してからコミットする

### 14.5 各ページに必ず入れる免責と説明

- 「本アプリは利用量制限を回避・突破するものではない」旨（トップと FAQ の両方）
- 「Xcode 専用である。VS Code / ターミナルの Claude Code には公式の自動継続機能があるため対象外」という説明
- 「Mac App Store では配布していない。Accessibility 権限を必要とするアプリはサンドボックスの制約により Store に出せないため」という説明
- 「Developer ID 署名と notarization 済みであること」、および Gatekeeper の初回起動手順
- 「Anthropic および Apple の公式製品ではない」という明記

### 14.6 ポートフォリオサイトとの相互リンク（必須）

以下のリンクを必ず設置します。

**本サイト → ポートフォリオ**

- 全ページ共通のフッターに、ポートフォリオハブへのリンクを置く
  - 日本語版のリンク先: `https://isitest1.github.io/portfolio-hub/ja`
  - 英語版のリンク先: ポートフォリオハブの英語版 URL（存在する場合はそれ、なければ上記を使用）
- トップページには、フッターとは別に「作者の他のプロジェクト」セクションを設け、同じくポートフォリオハブへ導線を張る
- リンクは同一タブで開く（`target="_blank"` は使わない）

**ポートフォリオ → 本サイト**

- ポートフォリオハブ側のリポジトリに、本プロジェクトのカード／エントリを追加すること。リンク先は本サイトのトップページ（言語に応じて `/ja/` または `/en/`）
- この作業も本プロジェクトの完了条件に含めます。**片方向リンクで終わらせないこと。**

### 14.7 その他

- OGP / Twitter Card 用のメタタグと画像（`assets/og-image.png`）を用意する
- `docs/site/sitemap.xml` と `robots.txt` を置く
- GitHub リポジトリの About 欄に、サイト URL を設定する
- ダウンロードボタンは GitHub Releases の `/releases/latest` へのリンクにして、リリースごとの手動更新を不要にする

---

## 15. 開発環境：Dev Container

開発は VS Code の Dev Container 上で行います。設定は `.devcontainer/devcontainer.json` にあります。

### 15.1 前提として理解しておくこと（重要）

**Dev Container は Linux コンテナです。macOS アプリのビルドはできません。** これは設定の問題ではなく原理的な制約です。

- `AppKit` / `SwiftUI` / `ApplicationServices`（Accessibility API）/ `UserNotifications` / `ServiceManagement` は macOS 専用であり、Linux 版 Swift には存在しません
- `xcodebuild` も Xcode も Linux には存在しません
- コード署名・notarization もホストの macOS でしか行えません

したがって、**役割を明確に分担します。**

| 作業 | 場所 |
|---|---|
| コードの編集、Claude Code による実装 | Dev Container |
| `SentinelCore` のビルドと単体テスト | Dev Container（`swift build` / `swift test`） |
| フォーマット・Lint | Dev Container |
| 公開サイト（`docs/site/`）の編集とプレビュー | Dev Container |
| ドキュメント執筆 | Dev Container |
| `App/` のビルド・実行・AX 動作確認 | **ホストの macOS**（Xcode / `xcodebuild`） |
| 署名・notarization・DMG 作成 | **ホストの macOS** |

**この制約こそが、第 4.1 章で `SentinelCore` を切り出す理由です。** ロジックを macOS 依存コードに混ぜ込むと、コンテナ上でテストできる範囲がゼロになり、Dev Container を使う意味が失われます。新しいロジックを書くときは、まず「これは `SentinelCore` に置けないか」を検討してください。

### 15.2 コンテナ内で必ず動くようにすること

- `swift build --package-path Packages/SentinelCore`
- `swift test --package-path Packages/SentinelCore`
- `docs/site/` のローカルプレビュー（ポート 8080）

CI（GitHub Actions）も、`SentinelCore` のテストは Linux ランナーで、`App/` のビルドは macOS ランナーで、と分けて実行します。

### 15.3 コンテナ内で `App/` を編集する際の注意

`App/` 配下は Linux ではコンパイルできないため、エディタ上で赤線が出ます。これは正常です。

- コンパイルエラーの有無をコンテナ内で確認できないため、**`App/` の変更はホストでのビルド確認とセットで行ってください**
- Claude Code に `App/` の実装をさせる場合、「ビルドが通ったか」を自動確認できません。変更を小さく刻み、こまめにホストで確認する運用にしてください
- `.vscode/settings.json` で、`App/` 配下の Swift 診断を抑制することを検討してもよいですが、必須ではありません

---

## 16. 追加で検討する価値のある機能（優先度順）

MVP には含めませんが、設計時に拡張余地を残してください。

1. **稼働レポート** — どの対象が何時間動き、何回停止し、どれだけ待たされたかの日次サマリ。共有プールをどう食い合っているかが可視化されると、実運用で最も効きます。
2. **Git セーフティネット** — 自動再開の直前に対象リポジトリで自動コミット（またはタグ付け）を行う。無人で Claude にコードを書かせる以上、巻き戻せることは必須級です。
3. **再開文言のテンプレート集** — 「続きから」「まずビルドを通してから続行」「変更点を要約してから続行」など、状況別に選べるようにする。
4. **メニューバーアイコンの状態表示** — 全体の状態（working / waiting / limited / error）を色と形で示す。
5. **手動操作** — メニューから "Resume now" / "Pause all" / "Snooze 1h"。
6. **週次制限への対応強化** — Claude Code の自動継続も週次制限はカバーしません。ここは本アプリが優位に立てる数少ない領域です。
7. **複数 Mac 対応** — 現状は対象外。設計を複雑にするので当面考慮しません。

---

## 17. やってはいけないこと

- 画面座標の決め打ちクリック
- 状態が `unknown` のときの自動送信
- 権限確認・質問に対する自動応答（既定で無効、明示的な有効化なしに動作させない）
- 制限到達時の短間隔リトライ連打
- チャット本文・ソースコードを外部 Webhook やログへ送出すること
- App Store 提出を前提とした設計
- 製品名への "Claude" / "Anthropic" の使用
- 「5 時間制限を突破できる」という趣旨の説明を README・UI・公開サイトに書くこと
- VS Code / ターミナルの Claude Code 対応を初版に含めること（スコープ外）
- 公開サイトを片方の言語だけ更新して放置すること
- **`SentinelCore` に `AppKit` / `ApplicationServices` / `SwiftUI` を import すること**
- Dev Container 内で macOS アプリのビルドを試みて時間を溶かすこと

---

## 18. 現時点で未確定・要検証の事項

実装前に、AX Inspector を使って実機で確認してください。推測でコードを書かないでください。

- Xcode 内の Claude パネルが、独立した AX ウィンドウなのか、Xcode ウィンドウの子要素なのか
- 入力欄の AX role と、`AXValue` の書き込みが可能かどうか
- 制限到達時のメッセージが AX ツリー上のどの要素に、どの文言で現れるか
- 送信ボタンが AX 要素として露出しているか、`AXPress` が効くか
- Xcode のウィンドウが最小化・非アクティブな状態でも AX ツリーを読めるか（読めない場合、監視方針の見直しが必要）
- Xcode の Claude 連携に、Claude Code の `/config` に相当する自動継続設定が後から追加されていないか（追加されていれば、本プロジェクトの前提が崩れます。着手前に必ず確認すること）

**これらの検証結果が出るまで、Detection と Automation の本実装に入らないでください。M1 の AX Inspector を先に完成させることが最短経路です。**
