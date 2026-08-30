# 検出パターン（`Patterns.json`）の書き方

状態判定に使う文字列はコードに直書きせず、`Patterns.json` に外出ししています
（CLAUDE.md 第 6.2 章）。Xcode 側の文言変更に、アプリの再ビルドなしで追従するためです。
設定画面からも編集・追加できます。

- 既定のパターン: `Packages/SentinelCore/Sources/SentinelCore/Resources/Patterns.json`
- モデル定義: `DetectionPattern` / `PatternSet`（`DetectionPatterns.swift`）
- 評価: `DetectionEngine` が `patterns` を上から順に走査し、**最初にマッチしたルールを採用**します。

## スキーマ

```jsonc
{
  "version": 1,
  "panelHints": {                     // 省略可。全ウィンドウの AX ツリーから
    "identifiers": ["claude-panel"],  // Claude パネルの部分木を先に絞り込む
    "anchorTexts": ["ask claude"],    // これを含む最小の部分木を候補にする
    "containerRoles": ["AXGroup"]     // 候補にするコンテナの role（省略可）
  },
  "patterns": [
    {
      "id": "session-limit",          // 一意。ログや設定画面で参照される
      "outcome": "sessionLimited",    // 下表のいずれか
      "anyOf": ["usage limit reached", "limit resets"], // どれか 1 つを含めばマッチ
      "allOf": [],                    // すべて含む必要がある（省略可）
      "noneOf": ["weekly"],           // 1 つでも含めば不成立（省略可）
      "role": null,                   // 指定時はその AX role のテキストのみ対象（省略可）
      "caseSensitive": false,         // 省略時 false
      "enabled": true,                // 省略時 true
      "note": "任意の説明"
    }
  ]
}
```

`anyOf` と `allOf` がどちらも空のルールは、常に不成立です（誤爆防止）。

## `outcome` の値と `SessionState` の対応

| `outcome` | 結果の `SessionState` | 備考 |
|---|---|---|
| `idle` | `.idle` | |
| `working` | `.working` | |
| `awaitingContinue` | `.awaitingContinue` | 自動再開の対象 |
| `sessionLimited` | `.sessionLimited(resetAt:)` | マッチしたテキストに `ResetTimeParser` を適用 |
| `weeklyLimited` | `.weeklyLimited(resetAt:)` | 同上。**必ず `sessionLimited` より前に置く** |
| `awaitingApproval` | `.awaitingApproval` | 自動応答しない（通知のみ） |
| `awaitingUserAnswer` | `.awaitingUserAnswer` | 自動応答しない（通知のみ） |
| `errored` | `.errored(message:)` | マッチしたテキスト断片を message に格納 |
| `completed` | `.completed` | |

どのルールにもマッチしない場合は `.unknown` になります。`.unknown` を `.working` と
誤認させないでください（CLAUDE.md 第 6.2 / 17 章）。

## パネルの絞り込み（`panelHints`）

`DetectionEngine.classify` は、パターン評価の前に `panelHints` を使って
Claude パネルの部分木を特定します（`locatePanel`）。

1. `identifiers` に一致する `AXIdentifier` を持つノード（先頭から順に、最優先）
2. `anchorTexts` のいずれかを部分木テキストに含み、`containerRoles`（指定時）に
   合致する **最小の部分木**
3. どれも当たらなければツリー全体にフォールバック（検出は失敗しない。走査量が増えるだけ）

結果の `panelLocated` で絞り込めたかどうかが分かります。`identifiers` は実機の
AX ダンプが取れてから埋めてください（`docs/accessibility-tree.md`）。

## 「Test Detection」向けの near-miss

`classify` の結果には `nearMisses`（惜しかったルール）が入ります。

| 理由 | 意味 |
|---|---|
| `wouldMatchIfEnabled` | 文言は一致したが `enabled: false` |
| `blockedByNoneOf(term)` | 文言は一致したが `noneOf` の `term` も出現した |
| `blockedByRole` | 文言はツリー内にあるが、指定 `role` のノード上には無い |

設定画面の "Test Detection" はこれを表示して、ユーザーがルールを調整できるようにします。

## 順序の注意

- **より具体的なルールを先に**置きます。特に `weekly-limit` は `session-limit` より前に必要です
  （週次のメッセージにも "limit" が含まれるため）。
- `?` のような広すぎるトークンだけのルールは既定で `enabled: false` にしています。実機の
  AX ダンプで文言を確認してから絞り込んで有効化してください。

## リセット時刻の抽出

`sessionLimited` / `weeklyLimited` にマッチすると、`DetectionEngine` はまず
「トリガー文字列を含むテキスト断片」に対して `ResetTimeParser.parse` を試し、
次に全断片へフォールバックします。認識できる書式は
[`ResetTimeParser`](../Packages/SentinelCore/Sources/SentinelCore/ResetTimeParser.swift) のドキュメントコメントを参照してください。

パース結果（`resetParse`）は必ずログと UI に表示し、ユーザーが誤りに気づけるようにします
（CLAUDE.md 第 6.3 章）。
